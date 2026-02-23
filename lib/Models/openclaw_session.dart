/// Represents an active session on an OpenClaw Gateway.
class OpenClawSession {
  final String sessionKey;
  final String? agentId;
  final String? channel;
  final DateTime? lastActivity;
  final int messageCount;
  final String connectionId;

  OpenClawSession({
    required this.sessionKey,
    this.agentId,
    this.channel,
    this.lastActivity,
    this.messageCount = 0,
    required this.connectionId,
  });

  factory OpenClawSession.fromJson(
    Map<String, dynamic> json, {
    required String connectionId,
  }) {
    return OpenClawSession(
      sessionKey: json['sessionKey'] ?? json['key'] ?? '',
      agentId: json['agentId'] ?? json['agent'],
      channel: json['channel'],
      lastActivity: json['lastActivity'] != null
          ? DateTime.tryParse(json['lastActivity'].toString())
          : null,
      messageCount: json['messageCount'] ?? json['messages'] ?? 0,
      connectionId: connectionId,
    );
  }

  /// A short display name for the session key.
  String get shortKey {
    if (sessionKey.length <= 30) return sessionKey;
    return '${sessionKey.substring(0, 27)}...';
  }
}

/// A single message from a session transcript.
class OpenClawSessionMessage {
  final String role;
  final String content;
  final DateTime? timestamp;

  OpenClawSessionMessage({
    required this.role,
    required this.content,
    this.timestamp,
  });

  factory OpenClawSessionMessage.fromJson(Map<String, dynamic> json) {
    return OpenClawSessionMessage(
      role: json['role'] ?? 'unknown',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())
          : null,
    );
  }
}
