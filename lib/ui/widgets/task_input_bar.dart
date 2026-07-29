import 'package:flutter/material.dart';

class TaskInputBar extends StatefulWidget {
  const TaskInputBar({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<TaskInputBar> createState() => _TaskInputBarState();
}

class _TaskInputBarState extends State<TaskInputBar> {
  final _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'Assign a task to the agent…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _submit,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
