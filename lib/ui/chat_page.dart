import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/agent_state.dart';
import '../models/log_entry.dart';
import '../services/session_service.dart';
import 'model_manager_page.dart';
import 'widgets/agent_log_view.dart';
import 'widgets/approval_banner.dart';
import 'widgets/task_input_bar.dart';

/// One chat's transcript + controls — the "Claude Code" half of the app
/// (an agent working a task), scoped to a single conversation out of
/// however many the user has (the "Claude mobile app" half, see
/// ChatListPage).
class ChatPage extends StatefulWidget {
  const ChatPage(
      {super.key, required this.sessionId, required this.initialTitle});

  final String sessionId;
  final String initialTitle;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _service = FlutterBackgroundService();
  final _sessions = SessionService.instance;
  Timer? _pollTimer;

  AgentState _state = AgentState.initial();
  List<LogEntry> _log = [];
  bool _modelLoaded = false;
  bool _serviceRunning = false;
  String? _runningSessionId;
  String _title = '';

  bool get _isThisSessionRunning => _runningSessionId == widget.sessionId;
  bool get _isBusyElsewhere =>
      _runningSessionId != null && _runningSessionId != widget.sessionId;

  @override
  void initState() {
    super.initState();
    _title = widget.initialTitle;
    _sessions.setActiveSessionId(widget.sessionId);
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final running = await _service.isRunning();
    final state = _sessions.loadStateWith(prefs, widget.sessionId);
    final log = _sessions.loadLogWith(prefs, widget.sessionId);

    if (!mounted) return;
    setState(() {
      _state = state;
      _log = log;
      _modelLoaded = prefs.getBool(StorageKeys.modelLoaded) ?? false;
      _serviceRunning = running;
      _runningSessionId = prefs.getString(StorageKeys.runningSessionId);
    });
  }

  Future<void> _assignTask(String task) async {
    if (!_serviceRunning) {
      _service.startService();
      // Give the isolate a moment to spin up before it can receive events.
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _service.invoke('setTask', {'task': task, 'sessionId': widget.sessionId});
  }

  Future<void> _stopAgent() async {
    _service.invoke('stopLoop');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.stopRequested, true);
  }

  Future<void> _setApprovalDecision(String decision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.approvalDecision, decision);
  }

  Future<void> _sendHumanReply(String reply) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.humanReply, reply);
  }

  Future<void> _openModelManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ModelManagerPage()),
    );
    _service.invoke('reloadModel');
    await _refresh();
  }

  Future<void> _renameChat() async {
    final controller = TextEditingController(text: _title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    await _sessions.renameSession(widget.sessionId, newTitle);
    if (!mounted) return;
    setState(() => _title = newTitle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _renameChat,
          child: Text(_title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ActionChip(
              avatar: Icon(
                _modelLoaded ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: _modelLoaded ? Colors.greenAccent : Colors.white54,
              ),
              label: Text(_modelLoaded ? 'Loaded' : 'Unloaded'),
              visualDensity: VisualDensity.compact,
              onPressed: _openModelManager,
            ),
          ),
          IconButton(
            tooltip: 'Stop agent',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: _isThisSessionRunning ? _stopAgent : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_state.currentTask.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Task: ${_state.currentTask} · ${_state.status.name} · iter ${_state.iteration}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ),
          if (_isBusyElsewhere)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'The agent is busy in another chat right now. '
                'Stop it there before assigning a task here — only one '
                'chat can run at a time.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ApprovalBanner(
            state: _state,
            onApprove: () => _setApprovalDecision('approve'),
            onDeny: () => _setApprovalDecision('deny'),
            onReply: _sendHumanReply,
          ),
          Expanded(child: AgentLogView(entries: _log)),
          TaskInputBar(onSubmit: _assignTask),
        ],
      ),
    );
  }
}
