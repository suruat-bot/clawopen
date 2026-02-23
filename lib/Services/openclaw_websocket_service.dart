import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:clawopen/Models/ollama_message.dart';
import 'package:clawopen/Models/openclaw_event.dart';
import 'package:clawopen/Models/openclaw_node.dart';

/// Persistent WebSocket connection to an OpenClaw Gateway.
///
/// Handles the challenge/response handshake, request-response pattern,
/// event broadcasting, and auto-reconnect with exponential backoff.
class OpenClawWebSocketService {
  final String baseUrl;
  final String? authToken;
  final String agentId;
  final String connectionId;

  /// Device token received from hello-ok, persisted across reconnects.
  String? deviceToken;

  /// Called when a new deviceToken is received from the gateway.
  final void Function(String)? onNewDeviceToken;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _eventController = StreamController<OpenClawEvent>.broadcast();
  Stream<OpenClawEvent> get events => _eventController.stream;

  int _requestIdCounter = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};

  OpenClawWsState _state = OpenClawWsState.disconnected;
  OpenClawWsState get state => _state;

  final _stateController = StreamController<OpenClawWsState>.broadcast();
  Stream<OpenClawWsState> get stateStream => _stateController.stream;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;

  OpenClawWebSocketService({
    required this.baseUrl,
    this.authToken,
    this.agentId = 'main',
    required this.connectionId,
    this.deviceToken,
    this.onNewDeviceToken,
  });

  /// Converts http(s) URL to ws(s) URL.
  String get _wsUrl {
    var url = baseUrl;
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'ws://$url';
    }
    // Remove trailing slash
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  /// Connect to the gateway WebSocket.
  Future<void> connect() async {
    if (_state == OpenClawWsState.connecting ||
        _state == OpenClawWsState.connected) {
      return;
    }

    _intentionalDisconnect = false;
    _setState(OpenClawWsState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _setState(OpenClawWsState.error);
          _scheduleReconnect();
        },
        onDone: () {
          _setState(OpenClawWsState.disconnected);
          if (!_intentionalDisconnect) {
            _scheduleReconnect();
          }
        },
      );

      // Wait for handshake — the gateway sends connect.challenge first
      await _performHandshake().timeout(const Duration(seconds: 10));

      _reconnectAttempts = 0;
      _setState(OpenClawWsState.connected);
    } catch (e) {
      _setState(OpenClawWsState.error);
      await _cleanup();
      _scheduleReconnect();
    }
  }

  /// Disconnect cleanly.
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _cleanup();
    _setState(OpenClawWsState.disconnected);
  }

  /// Send a request and await response.
  Future<Map<String, dynamic>> sendRequest(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (_state != OpenClawWsState.connected || _channel == null) {
      throw Exception('WebSocket not connected');
    }

    final id = ++_requestIdCounter;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final frame = {
      'type': 'req',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    _channel!.sink.add(json.encode(frame));

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request $method timed out');
      },
    );
  }

  /// Read the full gateway config (channels, agents, etc.).
  Future<Map<String, dynamic>> getConfig() async {
    return await sendRequest('config.get');
  }

  /// Merge-patch the gateway config.
  /// Example: `{ 'channels': { 'telegram': { 'enabled': false } } }`
  Future<void> patchConfig(Map<String, dynamic> patch) async {
    await sendRequest('config.patch', patch);
  }

  /// Get live status for all channels.
  Future<Map<String, dynamic>> getChannelsStatus() async {
    return await sendRequest('channels.status');
  }

  /// Send a chat message and stream the response.
  ///
  /// Handles both streaming (via chat.token events) and non-streaming
  /// (via the res frame) gateway responses.
  Stream<OllamaMessage> chatSendStream({
    required String message,
    String? sessionKey,
    String? systemPrompt,
    String? thinkingLevel,
    List<Map<String, dynamic>>? history,
  }) async* {
    if (_state != OpenClawWsState.connected || _channel == null) {
      throw Exception('WebSocket not connected');
    }

    final id = ++_requestIdCounter;
    final streamController = StreamController<OllamaMessage>();
    bool streamCompleted = false;

    // Listen for streaming token events correlated to this request
    StreamSubscription<OpenClawEvent>? eventSub;
    eventSub = events.listen((event) {
      if (streamCompleted || streamController.isClosed) return;

      final eventReqId = event.payload['id'];
      final matches = eventReqId == null || eventReqId == id;
      if (!matches) return;

      if (event.event == 'chat.token') {
        final token = event.payload['token'] as String? ?? '';
        if (token.isNotEmpty) {
          streamController.add(OllamaMessage(
            token,
            role: OllamaMessageRole.assistant,
            done: false,
          ));
        }
      } else if (event.event == 'chat.done') {
        streamCompleted = true;
        if (!streamController.isClosed) streamController.close();
      }
    });

    // Register pending request for the res frame
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final frame = {
      'type': 'req',
      'id': id,
      'method': 'chat.send',
      'params': {
        'agentId': agentId,
        'message': message,
        if (sessionKey != null && sessionKey.isNotEmpty)
          'sessionKey': sessionKey,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'systemPrompt': systemPrompt,
        if (thinkingLevel != null && thinkingLevel != 'off')
          'thinkingLevel': thinkingLevel,
        if (history != null && history.isNotEmpty) 'history': history,
      },
    };

    _channel!.sink.add(json.encode(frame));

    // Handle the res frame — non-streaming completion or final ack
    completer.future.then((payload) {
      if (streamCompleted || streamController.isClosed) return;
      // Extract content from various possible response shapes
      final content = payload['content'] as String?
          ?? payload['message'] as String?
          ?? (payload['choices'] as List?)?.firstOrNull?['message']?['content'] as String?;
      if (content != null && content.isNotEmpty) {
        streamController.add(OllamaMessage(
          content,
          role: OllamaMessageRole.assistant,
          done: true,
        ));
      }
      if (!streamController.isClosed) streamController.close();
    }).catchError((error) {
      if (!streamController.isClosed) {
        streamController.addError(error);
        streamController.close();
      }
    });

    yield* streamController.stream;
    await eventSub.cancel();
  }

  /// List paired nodes.
  Future<List<OpenClawNode>> listNodes() async {
    try {
      final result = await sendRequest('node.list');
      final nodes = result['nodes'] ?? result['payload'] ?? [];
      if (nodes is List) {
        return nodes
            .map((n) => OpenClawNode.fromJson(
                  n as Map<String, dynamic>,
                  connectionId: connectionId,
                ))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Describe a specific node.
  Future<OpenClawNode?> describeNode(String nodeId) async {
    try {
      final result = await sendRequest('node.describe', {'nodeId': nodeId});
      return OpenClawNode.fromJson(result, connectionId: connectionId);
    } catch (_) {
      return null;
    }
  }

  /// Get the tools catalog.
  Future<List<Map<String, dynamic>>> getToolsCatalog() async {
    try {
      final result = await sendRequest('tools.catalog');
      final tools = result['tools'] ?? [];
      if (tools is List) {
        return tools.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Resolve an approval request.
  Future<void> resolveApproval(String requestId, bool approved) async {
    await sendRequest('exec.approval.resolve', {
      'requestId': requestId,
      'approved': approved,
    });
  }

  // --- Private methods ---

  void _handleMessage(dynamic data) {
    try {
      final frame = json.decode(data as String) as Map<String, dynamic>;
      final type = frame['type'] as String?;

      switch (type) {
        case 'res':
          _handleResponse(frame);
          break;
        case 'event':
          // Handle connect.challenge directly here to avoid race condition:
          // the broadcast stream may not have listeners yet when the gateway
          // sends this event immediately after the WS connection opens.
          final eventName = frame['event'] as String?;
          if (eventName == 'connect.challenge') {
            _sendConnectRequest(
              frame['payload'] as Map<String, dynamic>? ?? {},
            );
          }
          _handleEvent(frame);
          break;
      }
    } catch (_) {
      // Malformed frame
    }
  }

  void _handleResponse(Map<String, dynamic> frame) {
    final id = frame['id'] as int?;
    if (id == null) return;

    final completer = _pendingRequests.remove(id);
    if (completer == null) return;

    final ok = frame['ok'] as bool? ?? false;
    if (ok) {
      completer.complete(frame['payload'] as Map<String, dynamic>? ?? {});
    } else {
      final error = frame['error'];
      completer.completeError(
        Exception(error is Map ? error['message'] ?? 'Unknown error' : '$error'),
      );
    }
  }

  void _handleEvent(Map<String, dynamic> frame) {
    final event = frame['event'] as String?;
    if (event == null) return;

    _eventController.add(OpenClawEvent(
      event: event,
      payload: frame['payload'] as Map<String, dynamic>? ?? {},
      seq: frame['seq'] as int?,
    ));
  }

  Completer<void>? _handshakeCompleter;

  Future<void> _performHandshake() async {
    _handshakeCompleter = Completer<void>();
    // connect.challenge is handled directly in _handleMessage() to avoid
    // a race condition where the gateway sends the event before this
    // broadcast-stream listener would be registered.
    return _handshakeCompleter!.future;
  }

  void _sendConnectRequest(Map<String, dynamic> challenge) {
    final id = ++_requestIdCounter;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final frame = {
      'type': 'req',
      'id': id,
      'method': 'connect',
      'params': {
        'protocolVersion': 1,
        'client': {
          'name': 'ClawOpen',
          'version': '1.0.0',
          'type': 'companion',
        },
        'role': 'operator',
        'scopes': ['operator.read', 'operator.write'],
        if (authToken != null && authToken!.isNotEmpty)
          'auth': {'token': authToken},
        if (deviceToken != null && deviceToken!.isNotEmpty)
          'device': {'token': deviceToken},
      },
    };

    _channel!.sink.add(json.encode(frame));

    completer.future.then((payload) {
      // Extract and persist the device token from hello-ok
      final newToken = payload['deviceToken'] as String?
          ?? payload['device']?['token'] as String?;
      if (newToken != null && newToken.isNotEmpty && newToken != deviceToken) {
        deviceToken = newToken;
        onNewDeviceToken?.call(newToken);
      }
      _handshakeCompleter?.complete();
    }).catchError((error) {
      _handshakeCompleter?.completeError(error);
    });
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    _reconnectTimer?.cancel();

    final delay = min(30, pow(2, _reconnectAttempts).toInt());
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      connect();
    });
  }

  Future<void> _cleanup() async {
    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    // Fail all pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('WebSocket disconnected'));
      }
    }
    _pendingRequests.clear();
  }

  void _setState(OpenClawWsState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _cleanup();
    _eventController.close();
    _stateController.close();
  }
}
