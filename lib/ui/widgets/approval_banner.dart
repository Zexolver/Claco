import 'package:flutter/material.dart';

import '../../models/agent_state.dart';

/// In-app equivalent of the lock-screen notification actions, so a user
/// who has the app open doesn't need to go through the notification shade
/// to approve/deny a risky action or answer an ask_human prompt.
class ApprovalBanner extends StatefulWidget {
  const ApprovalBanner({
    super.key,
    required this.state,
    required this.onApprove,
    required this.onDeny,
    required this.onReply,
  });

  final AgentState state;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final ValueChanged<String> onReply;

  @override
  State<ApprovalBanner> createState() => _ApprovalBannerState();
}

class _ApprovalBannerState extends State<ApprovalBanner> {
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.isWaitingForApproval) {
      return _banner(
        color: Colors.orange,
        title: 'Approval needed: ${state.pendingTool}',
        subtitle: state.pendingParams,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onDeny,
                child: const Text('Deny'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: widget.onApprove,
                child: const Text('Approve'),
              ),
            ),
          ],
        ),
      );
    }

    if (state.isWaitingForHuman) {
      return _banner(
        color: Colors.lightBlueAccent,
        title: 'Agent is asking:',
        subtitle: state.pendingParams,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                decoration: const InputDecoration(
                  hintText: 'Your reply…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final text = _replyController.text.trim();
                if (text.isEmpty) return;
                widget.onReply(text);
                _replyController.clear();
              },
              child: const Text('Reply'),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _banner({
    required Color color,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
