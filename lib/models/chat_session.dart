/// One entry in the chat list (spec: multiple chats, Claude-mobile-app
/// style). The session's actual transcript/agent state lives separately
/// under `StorageKeys.sessionState/sessionLog`; this is just the index row.
class ChatSessionMeta {
  ChatSessionMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSessionMeta copyWith({String? title, DateTime? updatedAt}) =>
      ChatSessionMeta(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatSessionMeta.fromJson(Map<String, dynamic> json) =>
      ChatSessionMeta(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'New chat',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
