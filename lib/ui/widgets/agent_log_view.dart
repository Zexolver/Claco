import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/log_entry.dart';

class AgentLogView extends StatelessWidget {
  const AgentLogView({super.key, required this.entries});

  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No activity yet.\nAssign a task below to start the agent.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[entries.length - 1 - index];
        return _LogTile(entry: entry);
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (entry.kind) {
      LogKind.thought => (
          'THOUGHT',
          Colors.lightBlueAccent,
          Icons.psychology_outlined
        ),
      LogKind.action => (
          'ACTION',
          const Color(0xFF00E676),
          Icons.bolt_outlined
        ),
      LogKind.observation => (
          'OBSERVATION',
          Colors.amberAccent,
          Icons.visibility_outlined
        ),
      LogKind.system => ('SYSTEM', Colors.white70, Icons.info_outline),
      LogKind.error => ('ERROR', Colors.redAccent, Icons.error_outline),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1A1A1A),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(entry.timestamp),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 4),
            MarkdownBody(
              data: entry.text.isEmpty ? '_(empty)_' : entry.text,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
