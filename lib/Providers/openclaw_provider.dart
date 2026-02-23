import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:reins/Models/connection.dart';
import 'package:reins/Models/openclaw_approval.dart';
import 'package:reins/Models/openclaw_event.dart';
import 'package:reins/Models/openclaw_node.dart';
import 'package:reins/Providers/connection_provider.dart';
import 'package:reins/Services/openclaw_websocket_service.dart';

/// Manages WebSocket connections to OpenClaw Gateways, exposing
/// real-time state: nodes, approvals, and connection status.
class OpenClawProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ConnectionProvider _connectionProvider;

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

  void _createWsService(Connection conn) {
    final service = OpenClawWebSocketService(
      baseUrl: conn.baseUrl,
      authToken: conn.authToken,
      agentId: conn.agentId ?? 'main',
      connectionId: conn.id,
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
