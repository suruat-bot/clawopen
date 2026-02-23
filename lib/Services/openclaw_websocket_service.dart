import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:reins/Models/openclaw_event.dart';
import 'package:reins/Models/openclaw_node.dart';

/// Persistent WebSocket connection to an OpenClaw Gateway.
///
/// Handles the challenge/response handshake, request-response pattern,
/// event broadcasting, and auto-reconnect with exponential backoff.
class OpenClawWebSocketService {
  final String baseUrl;
  final String? authToken;
  final String agentId;
  final String connectionId;

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

    // Listen for the connect.challenge event
    late StreamSubscription<OpenClawEvent> sub;
    sub = events.listen((event) {
      if (event.event == 'connect.challenge') {
        sub.cancel();
        // Respond with connect request
        _sendConnectRequest(event.payload);
      }
    });

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
      },
    };

    _channel!.sink.add(json.encode(frame));

    completer.future.then((_) {
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
