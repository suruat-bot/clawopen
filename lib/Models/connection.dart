import 'package:uuid/uuid.dart';

enum ConnectionType { ollama, openclaw, openaiCompatible }

class Connection {
  final String id;
  String name;
  ConnectionType type;
  String baseUrl;
  String? authToken;
  String agentId;
  bool isDefault;

  Connection({
    String? id,
    required this.name,
    required this.type,
    required this.baseUrl,
    this.authToken,
    this.agentId = 'main',
    this.isDefault = false,
  }) : id = id ?? const Uuid().v4();

  factory Connection.fromJson(Map<String, dynamic> map) {
    return Connection(
      id: map['id'] as String,
      name: map['name'] as String,
      type: ConnectionType.values.byName(map['type'] as String),
      baseUrl: map['baseUrl'] as String,
      authToken: map['authToken'] as String?,
      agentId: (map['agentId'] as String?) ?? 'main',
      isDefault: (map['isDefault'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'baseUrl': baseUrl,
        'authToken': authToken,
        'agentId': agentId,
        'isDefault': isDefault,
      };

  @override
  String toString() => name;
}
