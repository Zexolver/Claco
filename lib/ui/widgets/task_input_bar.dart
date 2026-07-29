import 'package:flutter/material.dart';

/// Bottom input area: a text field to assign a new task, and a stop button
/// to forcefully halt the background loop (spec 4.4).
class TaskInputBar extends StatelessWidget {
  const TaskInputBar({
    super.key,
    required this.controller,
    required this.isRunning,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isRunning;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isRunning,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: isRunning ? 'Agent is working…' : 'Assign a task to the agent…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (isRunning)
              IconButton.filledTonal(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                tooltip: 'Stop agent',
                color: Colors.redAccent,
              )
            else
              IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.send),
                tooltip: 'Assign task',
              ),
          ],
        ),
      ),
    );
  }
}
