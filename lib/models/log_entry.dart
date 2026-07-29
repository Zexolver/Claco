enum LogEntryKind {
  system,
  thought,
  action,
  observation,
  approvalRequested,
  approvalResolved,
  humanQuestion,
  humanReply,
  error,
  done,
}

/// A single line item rendered in the terminal/chat-style agent log.
class LogEntry {
  final LogEntryKind kind;
  final String text;
  final DateTime timestamp;

  LogEntry({required this.kind, required this.text, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        kind: LogEntryKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => LogEntryKind.system,
        ),
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}
