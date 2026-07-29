import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/log_entry.dart';

/// Terminal/chat-style view of the agent's thoughts, actions and
/// observations (spec 4.4), rendered as Markdown.
class AgentLogView extends StatelessWidget {
  const AgentLogView({super.key, required this.entries, required this.scrollController});

  final List<LogEntry> entries;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No activity yet. Assign a task below to start the agent.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, index) => _LogEntryTile(entry: entries[index]),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.entry});

  final LogEntry entry;

  (IconData, Color, String) _presentation() {
    switch (entry.kind) {
      case LogEntryKind.system:
        return (Icons.info_outline, Colors.blueGrey, 'System');
      case LogEntryKind.thought:
        return (Icons.psychology_outlined, Colors.tealAccent, 'Thought');
      case LogEntryKind.action:
        return (Icons.bolt_outlined, Colors.amberAccent, 'Action');
      case LogEntryKind.observation:
        return (Icons.visibility_outlined, Colors.lightBlueAccent, 'Observation');
      case LogEntryKind.approvalRequested:
        return (Icons.warning_amber_outlined, Colors.orangeAccent, 'Approval needed');
      case LogEntryKind.approvalResolved:
        return (Icons.check_circle_outline, Colors.greenAccent, 'Approval');
      case LogEntryKind.humanQuestion:
        return (Icons.help_outline, Colors.purpleAccent, 'Question');
      case LogEntryKind.humanReply:
        return (Icons.person_outline, Colors.purpleAccent, 'You');
      case LogEntryKind.error:
        return (Icons.error_outline, Colors.redAccent, 'Error');
      case LogEntryKind.done:
        return (Icons.flag_outlined, Colors.greenAccent, 'Done');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _presentation();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 4),
            MarkdownBody(
              data: entry.text.isEmpty ? '_(empty)_' : entry.text,
              selectable: true,
            ),
          ],
        ),
      ),
    );
  }
}
