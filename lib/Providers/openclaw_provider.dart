import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import 'package:clawopen/Models/connection.dart';
import 'package:clawopen/Models/ollama_message.dart';
import 'package:clawopen/Models/openclaw_approval.dart';
import 'package:clawopen/Models/openclaw_channel.dart';
import 'package:clawopen/Models/openclaw_event.dart';
import 'package:clawopen/Models/openclaw_node.dart';
import 'package:clawopen/Providers/connection_provider.dart';
import 'package:clawopen/Services/openclaw_websocket_service.dart';

/// Manages WebSocket connections to OpenClaw Gateways, exposing
/// real-time state: nodes, approvals, and connection status.
class OpenClawProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ConnectionProvider _connectionProvider;
  Box get _settingsBox => Hive.box('settings');

  /// One WebSocket per OpenClaw connection.
  final Map<String, OpenClawWebSocketService> _wsServices = {};
  final Map<String, StreamSubscription> _eventSubs = {};
  final Map<String, StreamSubscription> _stateSubs = {};

  List<OpenClawNode> _nodes = [];
  List<OpenClawNode> get nodes => List.unmodifiable(_nodes);

  List<OpenClawApprovalRequest> _pendingApprovals = [];
  List<OpenClawApprovalRequest> get pendingApprovals =>
      List.unmodifiable(_pendingApprovals);

  /// Aggregate WS state — connected if any connection is connected.
  OpenClawWsState get wsState {
    if (_wsServices.isEmpty) return OpenClawWsState.disconnected;
    if (_wsServices.values.any((s) => s.state == OpenClawWsState.connected)) {
      return OpenClawWsState.connected;
    }
    if (_wsServices.values.any((s) => s.state == OpenClawWsState.connecting)) {
      return OpenClawWsState.connecting;
    }
    if (_wsServices.values.any((s) => s.state == OpenClawWsState.error)) {
      return OpenClawWsState.error;
    }
    return OpenClawWsState.disconnected;
  }

  /// Get WS state for a specific connection.
  OpenClawWsState wsStateForConnection(String connectionId) {
    return _wsServices[connectionId]?.state ?? OpenClawWsState.disconnected;
  }

  /// Returns true if the WS for the given connection is connected.
  bool isWsConnected(String connectionId) {
    return _wsServices[connectionId]?.state == OpenClawWsState.connected;
  }

  OpenClawProvider({
    required ConnectionProvider connectionProvider,
  }) : _connectionProvider = connectionProvider {
    _connectionProvider.addListener(_onConnectionsChanged);
    WidgetsBinding.instance.addObserver(this);
    _syncConnections();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      connectAll();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      disconnectAll();
    }
  }

  /// Connect all OpenClaw WebSockets.
  Future<void> connectAll() async {
    final openclawConns = _connectionProvider.connections
        .where((c) => c.type == ConnectionType.openclaw);

    for (final conn in openclawConns) {
      if (!_wsServices.containsKey(conn.id)) {
        _createWsService(conn);
      }
      await _wsServices[conn.id]?.connect();
    }
  }

  /// Disconnect all WebSockets.
  Future<void> disconnectAll() async {
    for (final service in _wsServices.values) {
      await service.disconnect();
    }
  }

  /// Refresh the nodes list from all connected gateways.
  Future<void> refreshNodes() async {
    final allNodes = <OpenClawNode>[];
    for (final service in _wsServices.values) {
      if (service.state == OpenClawWsState.connected) {
        final nodes = await service.listNodes();
        allNodes.addAll(nodes);
      }
    }
    _nodes = allNodes;
    notifyListeners();
  }

  /// Resolve an approval request.
  Future<void> resolveApproval(String requestId, bool approved) async {
    final approval = _pendingApprovals
        .where((a) => a.requestId == requestId)
        .firstOrNull;
    if (approval == null) return;

    final service = _wsServices[approval.connectionId];
    if (service != null) {
      await service.resolveApproval(requestId, approved);
    }

    _pendingApprovals.removeWhere((a) => a.requestId == requestId);
    notifyListeners();
  }

  /// Send a chat message over WebSocket and stream the response.
  ///
  /// Throws if the connection is not WS-connected — callers should
  /// fall back to the HTTP path in that case.
  Stream<OllamaMessage> chatSendStream(
    String connectionId, {
    required String message,
    String? sessionKey,
    String? systemPrompt,
    String? thinkingLevel,
    List<Map<String, dynamic>>? history,
  }) {
    final service = _wsServices[connectionId];
    if (service == null || service.state != OpenClawWsState.connected) {
      throw Exception('WebSocket not connected for connection $connectionId');
    }
    return service.chatSendStream(
      message: message,
      sessionKey: sessionKey,
      systemPrompt: systemPrompt,
      thinkingLevel: thinkingLevel,
      history: history,
    );
  }

  /// Fetch channels from all connected gateways, grouped by connection.
  /// Throws if no gateways are connected or all fail.
  Future<List<OpenClawChannel>> getChannels() async {
    final result = <OpenClawChannel>[];
    Object? lastError;

    for (final entry in _wsServices.entries) {
      final connectionId = entry.key;
      final service = entry.value;
      if (service.state != OpenClawWsState.connected) continue;

      final conn = _connectionProvider.getConnection(connectionId);
      final connName = conn?.name ?? connectionId;

      try {
        final payload = await service.getConfig();
        final channels = _extractChannelsFromPayload(payload);

        for (final channelEntry in channels.entries) {
          final channelData = channelEntry.value as Map<String, dynamic>? ?? {};
          final enabled = channelData['enabled'] as bool? ?? true;
          result.add(OpenClawChannel(
            name: channelEntry.key,
            enabled: enabled,
            connectionId: connectionId,
            connectionName: connName,
          ));
        }
      } catch (e) {
        lastError = e;
      }
    }

    // If we got no channels but had errors, surface them
    if (result.isEmpty && lastError != null) {
      throw lastError;
    }

    return result;
  }

  /// Extracts the channels map from various config.get payload shapes.
  Map<String, dynamic> _extractChannelsFromPayload(Map<String, dynamic> payload) {
    // Shape 1: payload is the full config → { channels: {...}, gateway: {...} }
    if (payload['channels'] is Map) {
      return (payload['channels'] as Map).cast<String, dynamic>();
    }
    // Shape 2: payload wraps config → { config: { channels: {...} } }
    if (payload['config'] is Map) {
      final cfg = (payload['config'] as Map).cast<String, dynamic>();
      if (cfg['channels'] is Map) {
        return (cfg['channels'] as Map).cast<String, dynamic>();
      }
    }
    // Shape 3: payload wraps under data → { data: { channels: {...} } }
    if (payload['data'] is Map) {
      final data = (payload['data'] as Map).cast<String, dynamic>();
      if (data['channels'] is Map) {
        return (data['channels'] as Map).cast<String, dynamic>();
      }
    }
    return {};
  }

  /// Returns the raw top-level keys from config.get for debugging.
  Future<String> getRawConfigDebug() async {
    final connected = _wsServices.entries
        .where((e) => e.value.state == OpenClawWsState.connected);
    if (connected.isEmpty) return 'No connected gateways';

    try {
      final payload = await connected.first.value.getConfig();
      final keys = payload.keys.toList();
      final channelsVal = payload['channels'];
      return 'Top-level keys: $keys\n'
          'channels type: ${channelsVal.runtimeType}\n'
          'channels value: $channelsVal';
    } catch (e) {
      return 'config.get error: $e';
    }
  }

  /// Enable or disable a channel on the gateway.
  Future<void> setChannelEnabled(
    String connectionId,
    String channelName,
    bool enabled,
  ) async {
    final service = _wsServices[connectionId];
    if (service == null || service.state != OpenClawWsState.connected) {
      throw Exception('Not connected to gateway');
    }
    await service.patchConfig({
      'channels': {
        channelName: {'enabled': enabled},
      },
    });
  }

  // --- Private ---

  void _onConnectionsChanged() {
    _syncConnections();
  }

  void _syncConnections() {
    final openclawConns = _connectionProvider.connections
        .where((c) => c.type == ConnectionType.openclaw)
        .toList();

    final openclawIds = openclawConns.map((c) => c.id).toSet();

    // Remove services for deleted connections
    final toRemove =
        _wsServices.keys.where((id) => !openclawIds.contains(id)).toList();
    for (final id in toRemove) {
      _removeWsService(id);
    }

    // Add services for new connections
    for (final conn in openclawConns) {
      if (!_wsServices.containsKey(conn.id)) {
        _createWsService(conn);
        _wsServices[conn.id]?.connect();
      }
    }
  }

  String _deviceTokenKey(String connectionId) => 'deviceToken_$connectionId';

  void _createWsService(Connection conn) {
    final storedToken = _settingsBox.get(_deviceTokenKey(conn.id)) as String?;

    final service = OpenClawWebSocketService(
      baseUrl: conn.baseUrl,
      authToken: conn.authToken,
      agentId: conn.agentId ?? 'main',
      connectionId: conn.id,
      deviceToken: storedToken,
      onNewDeviceToken: (token) {
        _settingsBox.put(_deviceTokenKey(conn.id), token);
      },
    );

    _wsServices[conn.id] = service;

    // Listen to events
    _eventSubs[conn.id] = service.events.listen((event) {
      _handleEvent(event, conn.id);
    });

    // Listen to state changes
    _stateSubs[conn.id] = service.stateStream.listen((_) {
      notifyListeners();
      // Refresh nodes when connected
      if (service.state == OpenClawWsState.connected) {
        refreshNodes();
      }
    });
  }

  void _removeWsService(String connectionId) {
    _eventSubs[connectionId]?.cancel();
    _eventSubs.remove(connectionId);
    _stateSubs[connectionId]?.cancel();
    _stateSubs.remove(connectionId);
    _wsServices[connectionId]?.dispose();
    _wsServices.remove(connectionId);

    // Remove nodes and approvals for this connection
    _nodes.removeWhere((n) => n.connectionId == connectionId);
    _pendingApprovals.removeWhere((a) => a.connectionId == connectionId);
    notifyListeners();
  }

  void _handleEvent(OpenClawEvent event, String connectionId) {
    switch (event.event) {
      case 'exec.approval.requested':
        _pendingApprovals.add(
          OpenClawApprovalRequest.fromJson(
            event.payload,
            connectionId: connectionId,
          ),
        );
        notifyListeners();
        break;

      case 'exec.approval.resolved':
        final requestId = event.payload['requestId'] ?? event.payload['id'];
        if (requestId != null) {
          _pendingApprovals
              .removeWhere((a) => a.requestId == requestId.toString());
          notifyListeners();
        }
        break;

      case 'system-presence':
        // Could update node online/offline status
        refreshNodes();
        break;
    }
  }

  @override
  void dispose() {
    _connectionProvider.removeListener(_onConnectionsChanged);
    WidgetsBinding.instance.removeObserver(this);

    for (final sub in _eventSubs.values) {
      sub.cancel();
    }
    for (final sub in _stateSubs.values) {
      sub.cancel();
    }
    for (final service in _wsServices.values) {
      service.dispose();
    }

    super.dispose();
  }
}
