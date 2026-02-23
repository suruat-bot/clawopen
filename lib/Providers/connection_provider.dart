import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'package:reins/Models/connection.dart';
import 'package:reins/Models/ollama_model.dart';
import 'package:reins/Services/ollama_service.dart';
import 'package:reins/Services/openai_compatible_service.dart';
import 'package:reins/Services/openclaw_service.dart';

class ConnectionProvider extends ChangeNotifier {
  final Box _settingsBox;

  List<Connection> _connections = [];
  List<Connection> get connections => List.unmodifiable(_connections);

  final Map<String, dynamic> _serviceCache = {};
  final Map<String, bool> _connectionStatuses = {};
  Map<String, bool> get connectionStatuses => Map.unmodifiable(_connectionStatuses);

  Connection? get defaultConnection =>
      _connections.where((c) => c.isDefault).firstOrNull ??
      _connections.firstOrNull;

  ConnectionProvider(this._settingsBox) {
    _loadConnections();
  }

  void _loadConnections() {
    final raw = _settingsBox.get('connections');
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw as String);
        _connections = decoded
            .map((e) => Connection.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _connections = [];
      }
    } else {
      _migrateFromPhase1();
    }
  }

  void _migrateFromPhase1() {
    final connections = <Connection>[];

    final serverAddress = _settingsBox.get('serverAddress');
    if (serverAddress != null && serverAddress.toString().isNotEmpty) {
      connections.add(Connection(
        name: 'Ollama',
        type: ConnectionType.ollama,
        baseUrl: serverAddress.toString(),
        isDefault: true,
      ));
    }

    final openclawEnabled =
        _settingsBox.get('openclawEnabled', defaultValue: false);
    final openclawUrl =
        _settingsBox.get('openclawGatewayUrl', defaultValue: '');
    if (openclawEnabled == true &&
        openclawUrl != null &&
        openclawUrl.toString().isNotEmpty) {
      connections.add(Connection(
        name: 'OpenClaw Gateway',
        type: ConnectionType.openclaw,
        baseUrl: openclawUrl.toString(),
        authToken: _settingsBox.get('openclawAuthToken')?.toString(),
        agentId:
            _settingsBox.get('openclawAgentId', defaultValue: 'main').toString(),
        isDefault: connections.isEmpty,
      ));
    }

    _connections = connections;
    if (connections.isNotEmpty) {
      _saveConnections();
    }
  }

  void _saveConnections() {
    final encoded =
        jsonEncode(_connections.map((c) => c.toJson()).toList());
    _settingsBox.put('connections', encoded);
  }

  void addConnection(Connection connection) {
    if (_connections.isEmpty) {
      connection.isDefault = true;
    }
    _connections.add(connection);
    _saveConnections();
    notifyListeners();
  }

  void updateConnection(Connection connection) {
    final index = _connections.indexWhere((c) => c.id == connection.id);
    if (index != -1) {
      _connections[index] = connection;
      _serviceCache.remove(connection.id);
      _saveConnections();
      notifyListeners();
    }
  }

  void deleteConnection(String id) {
    final wasDefault =
        _connections.where((c) => c.id == id).firstOrNull?.isDefault ?? false;
    _connections.removeWhere((c) => c.id == id);
    _serviceCache.remove(id);
    _connectionStatuses.remove(id);

    if (wasDefault && _connections.isNotEmpty) {
      _connections.first.isDefault = true;
    }

    _saveConnections();
    notifyListeners();
  }

  void setDefault(String id) {
    for (final conn in _connections) {
      conn.isDefault = conn.id == id;
    }
    _saveConnections();
    notifyListeners();
  }

  Connection? getConnection(String id) {
    return _connections.where((c) => c.id == id).firstOrNull;
  }

  dynamic getService(String connectionId) {
    if (_serviceCache.containsKey(connectionId)) {
      return _serviceCache[connectionId];
    }

    final conn = _connections.firstWhere(
      (c) => c.id == connectionId,
      orElse: () => throw Exception('Connection not found: $connectionId'),
    );

    final dynamic service;
    switch (conn.type) {
      case ConnectionType.ollama:
        service = OllamaService(baseUrl: conn.baseUrl);
      case ConnectionType.openclaw:
        service = OpenClawService(
          baseUrl: conn.baseUrl,
          authToken: conn.authToken,
          agentId: conn.agentId,
        );
      case ConnectionType.openaiCompatible:
        service = OpenAICompatibleService(
          baseUrl: conn.baseUrl,
          apiKey: conn.authToken,
        );
    }

    _serviceCache[connectionId] = service;
    return service;
  }

  Future<bool> testConnection(Connection connection) async {
    try {
      switch (connection.type) {
        case ConnectionType.ollama:
          final response = await http
              .get(Uri.parse(connection.baseUrl))
              .timeout(const Duration(seconds: 5));
          return response.statusCode == 200;
        case ConnectionType.openclaw:
          final service = OpenClawService(
            baseUrl: connection.baseUrl,
            authToken: connection.authToken,
            agentId: connection.agentId,
          );
          return await service.testConnection();
        case ConnectionType.openaiCompatible:
          final service = OpenAICompatibleService(
            baseUrl: connection.baseUrl,
            apiKey: connection.authToken,
          );
          return await service.testConnection();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshAllStatuses() async {
    for (final conn in _connections) {
      _connectionStatuses[conn.id] = await testConnection(conn);
    }
    notifyListeners();
  }

  Future<void> refreshStatus(String connectionId) async {
    final conn = getConnection(connectionId);
    if (conn != null) {
      _connectionStatuses[conn.id] = await testConnection(conn);
      notifyListeners();
    }
  }

  Future<List<OllamaModel>> fetchModelsForConnection(
      String connectionId) async {
    final conn = _connections.firstWhere((c) => c.id == connectionId);
    final service = getService(connectionId);

    List<OllamaModel> models;
    switch (conn.type) {
      case ConnectionType.ollama:
        models = await (service as OllamaService).listModels();
      case ConnectionType.openclaw:
        models = await (service as OpenClawService).listModels();
      case ConnectionType.openaiCompatible:
        models = await (service as OpenAICompatibleService).listModels();
    }

    for (final m in models) {
      m.connectionId = connectionId;
      m.connectionName = conn.name;
    }

    return models;
  }

  Future<List<OllamaModel>> fetchAllModels() async {
    final allModels = <OllamaModel>[];
    for (final conn in _connections) {
      try {
        allModels.addAll(await fetchModelsForConnection(conn.id));
      } catch (_) {
        // Connection might be offline
      }
    }
    return allModels;
  }
}
