import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:reins/Models/ollama_model.dart';
import 'package:reins/Providers/connection_provider.dart';

/// A saved model entry — just enough info to identify a model across sessions.
class MyModel {
  final String name;
  final String connectionId;

  MyModel({required this.name, required this.connectionId});

  factory MyModel.fromJson(Map<String, dynamic> json) => MyModel(
        name: json['name'] as String,
        connectionId: json['connectionId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'connectionId': connectionId,
      };

  String get key => '$connectionId|$name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyModel && other.name == name && other.connectionId == connectionId;

  @override
  int get hashCode => Object.hash(name, connectionId);
}

class ModelProvider extends ChangeNotifier {
  final Box _settingsBox;
  static const _storageKey = 'myModels';

  List<MyModel> _myModels = [];
  List<MyModel> get myModels => List.unmodifiable(_myModels);

  /// Quick lookup set for checking membership.
  Set<String> _myModelKeys = {};

  bool _initialized = false;

  ModelProvider(this._settingsBox) {
    _load();
  }

  void _load() {
    final raw = _settingsBox.get(_storageKey);
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw as String);
        _myModels = decoded
            .map((e) => MyModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _myModelKeys = _myModels.map((m) => m.key).toSet();
        _initialized = true;
      } catch (_) {
        _myModels = [];
        _myModelKeys = {};
      }
    }
    // If no key exists, _initialized stays false — we'll auto-populate on first fetch.
  }

  void _save() {
    final encoded = jsonEncode(_myModels.map((m) => m.toJson()).toList());
    _settingsBox.put(_storageKey, encoded);
  }

  /// Whether a model is in "My Models".
  bool isAdded(String modelName, String? connectionId) {
    if (connectionId == null) return false;
    return _myModelKeys.contains('$connectionId|$modelName');
  }

  /// Add a model to "My Models".
  void addModel(OllamaModel model) {
    if (model.connectionId == null) return;
    final entry = MyModel(name: model.name, connectionId: model.connectionId!);
    if (_myModelKeys.contains(entry.key)) return;

    _myModels.add(entry);
    _myModelKeys.add(entry.key);
    _save();
    notifyListeners();
  }

  /// Remove a model from "My Models".
  void removeModel(String modelName, String connectionId) {
    final key = '$connectionId|$modelName';
    _myModels.removeWhere((m) => m.key == key);
    _myModelKeys.remove(key);
    _save();
    notifyListeners();
  }

  /// Fetches live OllamaModel objects filtered to only "My Models".
  /// On first use, auto-populates from all available models.
  Future<List<OllamaModel>> fetchMyModels(
      ConnectionProvider connectionProvider) async {
    final allModels = await connectionProvider.fetchAllModels();

    // First-use migration: add all models if no myModels key exists yet.
    if (!_initialized) {
      _myModels = allModels
          .where((m) => m.connectionId != null)
          .map((m) => MyModel(name: m.name, connectionId: m.connectionId!))
          .toList();
      _myModelKeys = _myModels.map((m) => m.key).toSet();
      _initialized = true;
      _save();
      notifyListeners();
      return allModels;
    }

    // Filter to only models in "My Models"
    return allModels.where((m) {
      if (m.connectionId == null) return false;
      return _myModelKeys.contains('${m.connectionId}|${m.name}');
    }).toList();
  }
}
