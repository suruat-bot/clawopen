import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notification_centre/notification_centre.dart';

import 'package:clawopen/Constants/constants.dart';
import 'package:clawopen/Models/chat_configure_arguments.dart';
import 'package:clawopen/Models/connection.dart';
import 'package:clawopen/Models/ollama_chat.dart';
import 'package:clawopen/Models/ollama_exception.dart';
import 'package:clawopen/Models/ollama_message.dart';
import 'package:clawopen/Models/ollama_model.dart';
import 'package:clawopen/Providers/connection_provider.dart';
import 'package:clawopen/Providers/model_provider.dart';
import 'package:clawopen/Providers/openclaw_provider.dart';
import 'package:clawopen/Services/database_service.dart';
import 'package:clawopen/Services/ollama_service.dart';
import 'package:clawopen/Services/openai_compatible_service.dart';
import 'package:clawopen/Services/openclaw_service.dart';

class ChatProvider extends ChangeNotifier {
  final ConnectionProvider _connectionProvider;
  final ModelProvider _modelProvider;
  final DatabaseService _databaseService;
  final OpenClawProvider? _openclawProvider;

  List<OllamaMessage> _messages = [];
  List<OllamaMessage> get messages => _messages;

  List<OllamaChat> _chats = [];
  List<OllamaChat> get chats => _chats;

  int _currentChatIndex = -1;
  int get selectedDestination => _currentChatIndex + 1;

  OllamaChat? get currentChat =>
      _currentChatIndex == -1 ? null : _chats[_currentChatIndex];

  final Map<String, OllamaMessage?> _activeChatStreams = {};

  bool get isCurrentChatStreaming =>
      _activeChatStreams.containsKey(currentChat?.id);

  bool get isCurrentChatThinking =>
      currentChat != null &&
      _activeChatStreams.containsKey(currentChat?.id) &&
      _activeChatStreams[currentChat?.id] == null;

  /// A map of chat errors, indexed by chat ID.
  final Map<String, OllamaException> _chatErrors = {};

  /// The current chat error. This is the error associated with the current chat.
  /// If there is no error, this will be `null`.
  ///
  /// This is used to display error messages in the chat view.
  OllamaException? get currentChatError => _chatErrors[currentChat?.id];

  /// The current chat configuration.
  ChatConfigureArguments get currentChatConfiguration {
    if (currentChat == null) {
      return _emptyChatConfiguration ?? ChatConfigureArguments.defaultArguments;
    } else {
      return ChatConfigureArguments(
        systemPrompt: currentChat!.systemPrompt,
        chatOptions: currentChat!.options,
        thinkingLevel: currentChat!.thinkingLevel,
      );
    }
  }

  /// The chat configuration for the empty chat.
  ChatConfigureArguments? _emptyChatConfiguration;

  ChatProvider({
    required ConnectionProvider connectionProvider,
    required ModelProvider modelProvider,
    required DatabaseService databaseService,
    OpenClawProvider? openclawProvider,
  })  : _connectionProvider = connectionProvider,
        _modelProvider = modelProvider,
        _databaseService = databaseService,
        _openclawProvider = openclawProvider {
    _initialize();
  }

  /// Returns the appropriate service for a chat based on its connectionId.
  /// Falls back to default connection if no connectionId is set, or uses
  /// legacy openclaw: prefix detection for old chats.
  dynamic _getServiceForChat(OllamaChat chat) {
    // If the chat has a connectionId, use it directly
    if (chat.connectionId != null) {
      try {
        return _connectionProvider.getService(chat.connectionId!);
      } catch (_) {
        // Connection might have been deleted, fall through to fallback
      }
    }

    // Legacy fallback: detect openclaw: prefix from Phase 1
    if (chat.model.startsWith('openclaw:')) {
      // Find the first openclaw connection
      final openclawConn = _connectionProvider.connections
          .where((c) => c.type == ConnectionType.openclaw)
          .firstOrNull;
      if (openclawConn != null) {
        return _connectionProvider.getService(openclawConn.id);
      }
    }

    // Fall back to default connection
    final defaultConn = _connectionProvider.defaultConnection;
    if (defaultConn != null) {
      return _connectionProvider.getService(defaultConn.id);
    }

    throw OllamaException('No connections configured. Add a connection in Settings.');
  }

  /// Returns the ConnectionType for a given chat.
  ConnectionType? _getConnectionTypeForChat(OllamaChat chat) {
    if (chat.connectionId != null) {
      final conn = _connectionProvider.getConnection(chat.connectionId!);
      if (conn != null) return conn.type;
    }
    // Legacy fallback
    if (chat.model.startsWith('openclaw:')) {
      return ConnectionType.openclaw;
    }
    final defaultConn = _connectionProvider.defaultConnection;
    return defaultConn?.type;
  }

  Future<void> _initialize() async {
    await _databaseService.open("ollama_chat.db");
    _chats = await _databaseService.getAllChats();
    notifyListeners();
  }

  void destinationChatSelected(int destination) {
    _currentChatIndex = destination - 1;

    if (destination == 0) {
      _resetChat();
    } else {
      _loadCurrentChat();
    }

    notifyListeners();
  }

  void _resetChat() {
    _currentChatIndex = -1;

    _messages.clear();

    notifyListeners();
  }

  Future<void> _loadCurrentChat() async {
    _messages = await _databaseService.getMessages(currentChat!.id);

    // Add the streaming message to the chat if it exists
    final streamingMessage = _activeChatStreams[currentChat!.id];
    if (streamingMessage != null) {
      _messages.add(streamingMessage);
    }

    // Unfocus the text field to dismiss the keyboard
    FocusManager.instance.primaryFocus?.unfocus();

    notifyListeners();
  }

  Future<void> createNewChat(OllamaModel model) async {
    final chat = await _databaseService.createChat(
      model.name,
      connectionId: model.connectionId,
    );

    _chats.insert(0, chat);
    _currentChatIndex = 0;

    if (_emptyChatConfiguration != null) {
      await updateCurrentChat(
        newSystemPrompt: _emptyChatConfiguration!.systemPrompt,
        newOptions: _emptyChatConfiguration!.chatOptions,
      );

      _emptyChatConfiguration = null;
    }

    notifyListeners();
  }

  Future<void> updateCurrentChat({
    String? newModel,
    String? newTitle,
    String? newSystemPrompt,
    OllamaChatOptions? newOptions,
    OpenClawThinkingLevel? newThinkingLevel,
  }) async {
    await updateChat(
      currentChat,
      newModel: newModel,
      newTitle: newTitle,
      newSystemPrompt: newSystemPrompt,
      newOptions: newOptions,
      newThinkingLevel: newThinkingLevel,
    );
  }

  /// Updates the chat with the given parameters.
  ///
  /// If the chat is `null`, it updates the empty chat configuration.
  Future<void> updateChat(
    OllamaChat? chat, {
    String? newModel,
    String? newTitle,
    String? newSystemPrompt,
    OllamaChatOptions? newOptions,
    OpenClawThinkingLevel? newThinkingLevel,
  }) async {
    if (chat == null) {
      final chatOptions = newOptions ?? _emptyChatConfiguration?.chatOptions;
      _emptyChatConfiguration = ChatConfigureArguments(
        systemPrompt: newSystemPrompt ?? _emptyChatConfiguration?.systemPrompt,
        chatOptions: chatOptions ?? OllamaChatOptions(),
      );
    } else {
      await _databaseService.updateChat(
        chat,
        newModel: newModel,
        newTitle: newTitle,
        newSystemPrompt: newSystemPrompt,
        newOptions: newOptions,
        newThinkingLevel: newThinkingLevel?.name,
      );

      final chatIndex = _chats.indexWhere((c) => c.id == chat.id);

      if (chatIndex != -1) {
        _chats[chatIndex] = (await _databaseService.getChat(chat.id))!;
        notifyListeners();
      } else {
        throw OllamaException("Chat not found.");
      }
    }
  }

  Future<void> deleteCurrentChat() async {
    final chat = currentChat;
    if (chat == null) return;

    _resetChat();

    _chats.remove(chat);
    _activeChatStreams.remove(chat.id);

    await _databaseService.deleteChat(chat.id);
  }

  Future<void> sendPrompt(String text, {List<File>? images}) async {
    // Save the chat where the prompt was sent
    final associatedChat = currentChat!;

    // Create a user prompt message and add it to the chat
    final prompt = OllamaMessage(
      text.trim(),
      images: images,
      role: OllamaMessageRole.user,
    );
    _messages.add(prompt);

    notifyListeners();

    // Save the user prompt to the database
    await _databaseService.addMessage(prompt, chat: associatedChat);

    // Initialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat);
  }

  Future<void> _initializeChatStream(OllamaChat associatedChat) async {
    // Send a notification to inform generation begin
    NotificationCenter().postNotification(NotificationNames.generationBegin);

    // Clear the active chat streams to cancel the previous stream
    _activeChatStreams.remove(associatedChat.id);

    // Clear the error message associated with the chat
    if (_chatErrors.remove(associatedChat.id) != null) {
      notifyListeners();
      // Wait for a short time to show the user that the error message is cleared
      await Future.delayed(Duration(milliseconds: 250));
    }

    // Update the chat list to show the latest chat at the top
    _moveCurrentChatToTop();

    // Add the chat to the active chat streams to show the thinking indicator
    _activeChatStreams[associatedChat.id] = null;
    // Notify the listeners to show the thinking indicator
    notifyListeners();

    // Stream the Ollama message
    OllamaMessage? ollamaMessage;

    try {
      ollamaMessage = await _streamOllamaMessage(associatedChat);
    } on OllamaException catch (error) {
      _chatErrors[associatedChat.id] = error;
    } on SocketException catch (_) {
      _chatErrors[associatedChat.id] = OllamaException(
        'Network connection lost. Check your server address or internet connection.',
      );
    } catch (error) {
      _chatErrors[associatedChat.id] = OllamaException("Something went wrong.");
    } finally {
      // Remove the chat from the active chat streams
      _activeChatStreams.remove(associatedChat.id);
      notifyListeners();
    }

    // Save the Ollama message to the database
    if (ollamaMessage != null) {
      await _databaseService.addMessage(ollamaMessage, chat: associatedChat);
    }
  }

  /// Returns a chat stream for an OpenClaw connection.
  /// Uses WebSocket chat.send when WS is connected, falls back to HTTP.
  Stream<OllamaMessage> _openclawChatStream(
    OllamaChat chat,
    OpenClawService httpService,
  ) {
    final connId = chat.connectionId;
    if (connId != null &&
        _openclawProvider != null &&
        _openclawProvider!.isWsConnected(connId)) {
      // Use native WS chat.send
      final lastUserMsg = _messages.last;

      // Build history from all messages except the last user message
      final history = _messages
          .sublist(0, _messages.length - 1)
          .map((m) => {
                'role': m.role == OllamaMessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final thinkingLevelName = chat.thinkingLevel?.name;

      return _openclawProvider!.chatSendStream(
        connId,
        message: lastUserMsg.content,
        sessionKey: chat.effectiveSessionUser,
        systemPrompt: chat.systemPrompt,
        thinkingLevel: (thinkingLevelName != null && thinkingLevelName != 'off')
            ? thinkingLevelName
            : null,
        history: history,
      );
    }
    // Fallback to HTTP streaming
    return httpService.chatStream(_messages, chat: chat);
  }

  Future<OllamaMessage?> _streamOllamaMessage(OllamaChat associatedChat) async {
    if (_messages.isEmpty) return null;

    // Route to the correct backend based on the chat's connection
    final service = _getServiceForChat(associatedChat);
    final Stream<OllamaMessage> stream;
    if (service is OllamaService) {
      stream = service.chatStream(_messages, chat: associatedChat);
    } else if (service is OpenClawService) {
      stream = _openclawChatStream(associatedChat, service);
    } else if (service is OpenAICompatibleService) {
      stream = service.chatStream(_messages, chat: associatedChat);
    } else {
      throw OllamaException('Unknown service type');
    }

    OllamaMessage? streamingMessage;
    OllamaMessage? receivedMessage;

    await for (receivedMessage in stream) {
      // If the chat id is not in the active chat streams, it means the stream
      // is cancelled by the user. So, we need to break the loop.
      if (_activeChatStreams.containsKey(associatedChat.id) == false) {
        streamingMessage?.createdAt = DateTime.now();
        return streamingMessage;
      }

      // Ignore empty initial messages, preventing disruption of the thinking indicator
      if (receivedMessage.content.isEmpty && streamingMessage == null) {
        continue;
      }

      if (streamingMessage == null) {
        // Keep the first received message to add the content of the following messages
        streamingMessage = receivedMessage;

        // Update the active chat streams key with the ollama message
        // to be able to show the stream in the chat.
        // We also use this when the user switches between chats while streaming.
        _activeChatStreams[associatedChat.id] = streamingMessage;

        // Be sure the user is in the same chat while the initial message is received
        if (associatedChat.id == currentChat?.id) {
          _messages.add(streamingMessage);
        }
      } else {
        streamingMessage.content += receivedMessage.content;
      }

      notifyListeners();
    }

    if (receivedMessage != null) {
      // Update the metadata of the streaming message with the last received message
      streamingMessage?.updateMetadataFrom(receivedMessage);
    }

    // Update created at time to the current time when the stream is finished
    streamingMessage?.createdAt = DateTime.now();

    return streamingMessage;
  }

  Future<void> regenerateMessage(OllamaMessage message) async {
    final associatedChat = currentChat!;

    final messageIndex = _messages.indexOf(message);
    if (messageIndex == -1) return;

    final includeMessage = (message.role == OllamaMessageRole.user ? 1 : 0);

    final stayedMessages = _messages.sublist(0, messageIndex + includeMessage);
    final removeMessages = _messages.sublist(messageIndex + includeMessage);

    _messages = stayedMessages;
    notifyListeners();

    await _databaseService.deleteMessages(removeMessages);

    // Reinitialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat);
  }

  Future<void> retryLastPrompt() async {
    if (_messages.isEmpty) return;

    final associatedChat = currentChat!;

    if (_messages.last.role == OllamaMessageRole.assistant) {
      final message = _messages.removeLast();
      await _databaseService.deleteMessage(message.id);
    }

    // Reinitialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat);

    notifyListeners();
  }

  Future<void> updateMessage(
    OllamaMessage message, {
    String? newContent,
  }) async {
    message.content = newContent ?? message.content;
    notifyListeners();

    await _databaseService.updateMessage(message, newContent: newContent);
  }

  Future<void> deleteMessage(OllamaMessage message) async {
    await _databaseService.deleteMessage(message.id);

    // If the message is in the chat, remove it from the chat
    if (_messages.remove(message)) {
      notifyListeners();
    }
  }

  void cancelCurrentStreaming() {
    _activeChatStreams.remove(currentChat?.id);
    notifyListeners();
  }

  void _moveCurrentChatToTop() {
    if (_currentChatIndex == 0) return;

    final chat = _chats.removeAt(_currentChatIndex);
    _chats.insert(0, chat);
    _currentChatIndex = 0;
  }

  Future<List<OllamaModel>> fetchAvailableModels() async {
    return _modelProvider.fetchMyModels(_connectionProvider);
  }

  Future<void> saveAsNewModel(String modelName) async {
    final associatedChat = currentChat;
    if (associatedChat == null) {
      throw OllamaException("No chat is selected.");
    }

    final connType = _getConnectionTypeForChat(associatedChat);
    if (connType != ConnectionType.ollama) {
      throw OllamaException("Saving as a new model is only supported for Ollama connections.");
    }

    final service = _getServiceForChat(associatedChat);
    if (service is OllamaService) {
      await service.createModel(
        modelName,
        chat: associatedChat,
        messages: _messages.toList(),
      );
    }
  }

  Future<void> generateTitleForCurrentChat() async {
    final associatedChat = currentChat;
    final message = _messages.firstOrNull;
    if (associatedChat == null || message == null) return;

    // Create a temp chat with necessary system prompt
    final chat = OllamaChat(
      model: associatedChat.model,
      systemPrompt: GenerateTitleConstants.systemPrompt,
      connectionId: associatedChat.connectionId,
    );

    final prompt = GenerateTitleConstants.prompt + message.content;

    final service = _getServiceForChat(associatedChat);
    Stream<OllamaMessage> stream;

    if (service is OllamaService) {
      stream = service.generateStream(prompt, chat: chat);
    } else {
      // OpenClaw and OpenAI-compatible providers use chatStream
      final titleMessages = [
        OllamaMessage(prompt, role: OllamaMessageRole.user),
      ];
      if (service is OpenClawService) {
        stream = service.chatStream(titleMessages, chat: chat);
      } else if (service is OpenAICompatibleService) {
        stream = service.chatStream(titleMessages, chat: chat);
      } else {
        return;
      }
    }

    var title = "";
    await for (final titleMessage in stream) {
      // Ignore empty initial messages, preventing empty title
      if (title.isEmpty && titleMessage.content.isEmpty) {
        continue;
      }

      title += titleMessage.content;

      // If <think> tag exists, do not stream chat title
      if (title.startsWith("<think>")) {
        await updateChat(associatedChat, newTitle: "Thinking for a title...");
      } else {
        await updateChat(associatedChat, newTitle: title);
      }
    }

    // Remove <think> tag and its content
    if (title.startsWith("<think>")) {
      title = title.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
    }

    // Save the title as the chat title
    await updateChat(associatedChat, newTitle: title.trim());
  }
}
