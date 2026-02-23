/// State of a WebSocket connection to an OpenClaw Gateway.
enum OpenClawWsState { disconnected, connecting, connected, error }

/// A real-time event received over the WebSocket connection.
class OpenClawEvent {
  final String event;
  final Map<String, dynamic> payload;
  final int? seq;

  OpenClawEvent({
    required this.event,
    required this.payload,
    this.seq,
  });

  factory OpenClawEvent.fromJson(Map<String, dynamic> json) {
    return OpenClawEvent(
      event: json['event'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      seq: json['seq'] as int?,
    );
  }
}
