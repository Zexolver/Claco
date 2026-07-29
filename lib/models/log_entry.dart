enum LogKind { thought, action, observation, system, error }

class LogEntry {
  LogEntry({
    required this.kind,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final LogKind kind;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        kind: LogKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => LogKind.system,
        ),
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}
