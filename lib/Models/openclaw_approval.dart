/// An approval request from the OpenClaw Gateway for a tool execution.
class OpenClawApprovalRequest {
  final String requestId;
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String? sessionKey;
  final DateTime requestedAt;
  final String connectionId;

  OpenClawApprovalRequest({
    required this.requestId,
    required this.toolName,
    this.toolInput = const {},
    this.sessionKey,
    required this.requestedAt,
    required this.connectionId,
  });

  factory OpenClawApprovalRequest.fromJson(
    Map<String, dynamic> json, {
    required String connectionId,
  }) {
    return OpenClawApprovalRequest(
      requestId: json['requestId'] ?? json['id'] ?? '',
      toolName: json['tool'] ?? json['toolName'] ?? 'unknown',
      toolInput: json['input'] ?? json['toolInput'] ?? {},
      sessionKey: json['sessionKey'],
      requestedAt: json['requestedAt'] != null
          ? DateTime.tryParse(json['requestedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      connectionId: connectionId,
    );
  }
}
