import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:reins/Models/ollama_chat.dart';
import 'package:reins/Models/ollama_exception.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:reins/Models/ollama_model.dart';

/// Service for communicating with any OpenAI-compatible API provider.
///
/// Works with OpenAI, Groq, OpenRouter, Together AI, NVIDIA NIM,
/// Mistral, DeepSeek, Fireworks AI, and any other provider that
/// implements the /v1/chat/completions endpoint.
class OpenAICompatibleService {
  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String? value) => _baseUrl = value ?? '';

  String? _apiKey;
  String? get apiKey => _apiKey;
  set apiKey(String? value) => _apiKey = value;

  OpenAICompatibleService({
    String? baseUrl,
    String? apiKey,
  })  : _baseUrl = baseUrl ?? '',
        _apiKey = apiKey;

  Map<String, String> get headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_apiKey';
    }
    return h;
  }

  Uri get _chatCompletionsUrl => Uri.parse('$baseUrl/v1/chat/completions');
  Uri get _modelsUrl => Uri.parse('$baseUrl/v1/models');

  /// Sends a chat message and streams the response.
  Stream<OllamaMessage> chatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
  }) async* {
    final request = http.Request("POST", _chatCompletionsUrl);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "messages": _prepareMessages(messages, chat.systemPrompt),
      "stream": true,
    });

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      await for (final message in _processSSEStream(response.stream)) {
        yield message;
      }
    } else if (response.statusCode == 401) {
      throw OllamaException("Authentication failed. Check your API key.");
    } else if (response.statusCode == 404) {
      throw OllamaException("Endpoint not found. Check your base URL.");
    } else if (response.statusCode == 429) {
      throw OllamaException("Rate limit exceeded. Please wait and try again.");
    } else {
      throw OllamaException("API error: ${response.statusCode}");
    }
  }

  Stream<OllamaMessage> _processSSEStream(Stream stream) async* {
    String buffer = '';

    await for (var chunk in stream.transform(utf8.decoder)) {
      chunk = buffer + chunk;
      buffer = '';

      final lines = LineSplitter.split(chunk);

      for (var line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          if (data == '[DONE]') {
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

  List<Map<String, dynamic>> _prepareMessages(
    List<OllamaMessage> messages,
    String? systemPrompt,
  ) {
    final result = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }

    for (final msg in messages) {
      result.add({
        'role': msg.role == OllamaMessageRole.user ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    return result;
  }

  /// Tests the connection by calling the models endpoint.
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        _modelsUrl,
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Lists available models from the provider's /v1/models endpoint.
  Future<List<OllamaModel>> listModels() async {
    try {
      final response = await http.get(
        _modelsUrl,
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final data = jsonBody['data'] as List<dynamic>? ?? [];

        return data.map((model) {
          final id = model['id'] as String? ?? '';
          final created = model['created'] as int?;
          final ownedBy = model['owned_by'] as String? ?? '';

          return OllamaModel(
            name: id,
            model: id,
            modifiedAt: created != null
                ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
                : DateTime.now(),
            size: 0,
            digest: id,
            details: OllamaModelDetails(
              parentModel: '',
              format: '',
              family: ownedBy,
              families: null,
              parameterSize: '',
              quantizationLevel: '',
            ),
          );
        }).toList();
      }
    } catch (_) {
      // Fall through to empty list
    }

    return [];
  }
}
