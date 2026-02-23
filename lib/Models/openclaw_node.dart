/// Represents a paired device node on an OpenClaw Gateway.
class OpenClawNode {
  final String nodeId;
  final String name;
  final String? platform;
  final List<String> capabilities;
  final bool isOnline;
  final DateTime? lastSeen;
  final String connectionId;

  OpenClawNode({
    required this.nodeId,
    required this.name,
    this.platform,
    this.capabilities = const [],
    this.isOnline = false,
    this.lastSeen,
    required this.connectionId,
  });

  factory OpenClawNode.fromJson(
    Map<String, dynamic> json, {
    required String connectionId,
  }) {
    return OpenClawNode(
      nodeId: json['nodeId'] ?? json['id'] ?? '',
      name: json['name'] ?? json['label'] ?? 'Unknown',
      platform: json['platform'],
      capabilities: (json['caps'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isOnline: json['online'] ?? json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'].toString())
          : null,
      connectionId: connectionId,
    );
  }

  /// Icon name for the platform.
  String get platformLabel {
    switch (platform?.toLowerCase()) {
      case 'ios':
        return 'iPhone';
      case 'android':
        return 'Android';
      case 'macos':
        return 'Mac';
      default:
        return platform ?? 'Device';
    }
  }
}
