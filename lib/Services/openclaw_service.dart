import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:clawopen/Models/ollama_chat.dart';
import 'package:clawopen/Models/ollama_exception.dart';
import 'package:clawopen/Models/ollama_message.dart';
import 'package:clawopen/Models/ollama_model.dart';

/// Service for communicating with an OpenClaw Gateway.
/// 
/// OpenClaw Gateway exposes an OpenAI-compatible /v1/chat/completions endpoint.
/// This service wraps that API to provide chat functionality alongside Ollama.
class OpenClawService {
  /// The base URL for the OpenClaw Gateway.
  /// Example: "http://192.168.1.100:17585" or "https://gateway.example.com"
  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String? value) => _baseUrl = value ?? "http://localhost:17585";

  /// The authentication token for the Gateway.
  String? _authToken;
  String? get authToken => _authToken;
  set authToken(String? value) => _authToken = value;

  /// The agent ID to use for requests (default: "main").
  String _agentId;
  String get agentId => _agentId;
  set agentId(String value) => _agentId = value;

  /// Optional session key for persistent sessions.
  String? _sessionKey;
  String? get sessionKey => _sessionKey;
  set sessionKey(String? value) => _sessionKey = value;

  /// Creates a new instance of the OpenClaw service.
  OpenClawService({
    String? baseUrl,
    String? authToken,
    String agentId = "main",
    String? sessionKey,
  })  : _baseUrl = baseUrl ?? "http://localhost:17585",
        _authToken = authToken,
        _agentId = agentId,
        _sessionKey = sessionKey;

  /// Constructs headers for API requests.
  Map<String, String> get headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'x-openclaw-agent-id': _agentId,
    };
    
    if (_authToken != null && _authToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    
    if (_sessionKey != null && _sessionKey!.isNotEmpty) {
      h['x-openclaw-session-key'] = _sessionKey!;
    }
    
    return h;
  }

  /// Constructs a URL for the chat completions endpoint.
  Uri get chatCompletionsUrl => Uri.parse('$baseUrl/v1/chat/completions');

  /// Sends a chat message and returns the response.
  Future<OllamaMessage> chat(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
  }) async {
    final response = await http.post(
      chatCompletionsUrl,
      headers: headers,
      body: json.encode({
        "model": "openclaw:$_agentId",
        "messages": await _prepareMessages(messages, chat.systemPrompt),
        "stream": false,
        "user": chat.effectiveSessionUser,
        if (chat.thinkingLevel != null && chat.thinkingLevel!.name != 'off')
          "thinking_level": chat.thinkingLevel!.name,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return _parseOpenAIResponse(jsonBody);
    } else if (response.statusCode == 401) {
      throw OllamaException("Authentication failed. Check your gateway token.");
    } else if (response.statusCode == 404) {
      throw OllamaException("Gateway endpoint not found. Is chatCompletions enabled?");
    } else if (response.statusCode == 500) {
      throw OllamaException("Gateway internal error.");
    } else {
      throw OllamaException("Gateway error: ${response.statusCode}");
    }
  }

  /// Sends a chat message and streams the response.
  Stream<OllamaMessage> chatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
  }) async* {
    final request = http.Request("POST", chatCompletionsUrl);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": "openclaw:$_agentId",
      "messages": await _prepareMessages(messages, chat.systemPrompt),
      "stream": true,
      "user": chat.effectiveSessionUser,
      if (chat.thinkingLevel != null && chat.thinkingLevel!.name != 'off')
        "thinking_level": chat.thinkingLevel!.name,
    });

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      await for (final message in _processSSEStream(response.stream)) {
        yield message;
      }
    } else if (response.statusCode == 401) {
      throw OllamaException("Authentication failed. Check your gateway token.");
    } else if (response.statusCode == 404) {
      throw OllamaException("Gateway endpoint not found. Is chatCompletions enabled?");
    } else {
      throw OllamaException("Gateway error: ${response.statusCode}");
    }
  }

  /// Processes Server-Sent Events (SSE) stream from OpenAI-compatible API.
  Stream<OllamaMessage> _processSSEStream(Stream stream) async* {
    String buffer = '';
    String accumulatedContent = '';

    await for (var chunk in stream.transform(utf8.decoder)) {
      chunk = buffer + chunk;
      buffer = '';

      final lines = LineSplitter.split(chunk);

      for (var line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          
          if (data == '[DONE]') {
            // Stream complete - yield final message with empty content
            // since the provider already accumulated all delta content
            yield OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              done: true,
            );
            return;
          }

          try {
            final jsonBody = json.decode(data);
            final delta = jsonBody['choices']?[0]?['delta'];
            
            if (delta != null && delta['content'] != null) {
              accumulatedContent += delta['content'];
              yield OllamaMessage(
                delta['content'],
                role: OllamaMessageRole.assistant,
                done: false,
              );
            }
          } catch (_) {
            buffer = line;
          }
        }
      }
    }
  }

  /// Converts OpenAI API response to OllamaMessage.
  OllamaMessage _parseOpenAIResponse(Map<String, dynamic> jsonBody) {
    final content = jsonBody['choices']?[0]?['message']?['content'] ?? '';
    return OllamaMessage(
      content,
      role: OllamaMessageRole.assistant,
      done: true,
    );
  }

  /// Prepares messages for the OpenAI chat format.
  Future<List<Map<String, dynamic>>> _prepareMessages(
    List<OllamaMessage> messages,
    String? systemPrompt,
  ) async {
    final result = <Map<String, dynamic>>[];

    // Add system prompt if provided
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }

    // Convert OllamaMessages to OpenAI format
    for (final msg in messages) {
      result.add({
        'role': msg.role == OllamaMessageRole.user ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    return result;
  }

  /// Tests the connection to the Gateway.
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Invokes a tool on the gateway via POST /tools/invoke.
  Future<dynamic> invokeTool(
    String tool, {
    String? action,
    Map<String, dynamic>? args,
    String? sessionKey,
  }) async {
    final body = <String, dynamic>{'tool': tool};
    if (action != null) body['action'] = action;
    if (args != null) body['args'] = args;
    if (sessionKey != null) body['sessionKey'] = sessionKey;

    final response = await http.post(
      Uri.parse('$baseUrl/tools/invoke'),
      headers: headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw OllamaException('Authentication failed.');
    } else if (response.statusCode == 404) {
      throw OllamaException('Tool not found or endpoint disabled.');
    } else {
      throw OllamaException('Tool invocation failed: ${response.statusCode}');
    }
  }

  /// Lists active sessions on the gateway.
  Future<List<Map<String, dynamic>>> listSessions() async {
    final result = await invokeTool('sessions_list', action: 'json');
    if (result is List) {
      return result.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Gets the transcript/history for a session.
  Future<List<Map<String, dynamic>>> getSessionHistory(String sessionKey) async {
    final result = await invokeTool(
      'sessions_history',
      args: {'sessionKey': sessionKey},
    );
    if (result is List) {
      return result.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Lists available agents (placeholder - OpenClaw doesn't have a list endpoint yet).
  /// Returns a single "main" model for now.
  Future<List<OllamaModel>> listModels() async {
    // OpenClaw doesn't expose a model list endpoint like Ollama.
    // Return the configured agent as a "model" for UI compatibility.
    return [
      OllamaModel(
        name: 'openclaw:$_agentId',
        model: 'openclaw:$_agentId',
        modifiedAt: DateTime.now(),
        size: 0,
        digest: '',
        details: OllamaModelDetails(
          parentModel: '',
          format: '',
          family: 'openclaw',
          families: null,
          parameterSize: '',
          quantizationLevel: '',
        ),
      ),
    ];
  }
}
