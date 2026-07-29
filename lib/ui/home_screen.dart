import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/agent_status.dart';
import '../models/log_entry.dart';
import '../services/storage_service.dart';
import 'widgets/agent_log_view.dart';
import 'widgets/model_status_chip.dart';
import 'widgets/task_input_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _taskController = TextEditingController();
  final _scrollController = ScrollController();
  final _storage = StorageService();

  final List<LogEntry> _entries = [];
  AgentStatus _status = const AgentStatus();
  String? _modelPath;
  bool _modelPresent = false;

  StreamSubscription<Map<String, dynamic>?>? _logSub;
  StreamSubscription<Map<String, dynamic>?>? _statusSub;

  @override
  void initState() {
    super.initState();
    _checkModel();
    _wireServiceStreams();
  }

  Future<void> _checkModel() async {
    final present = await _storage.isModelPresent;
    final file = await _storage.modelFile;
    if (!mounted) return;
    setState(() {
      _modelPresent = present;
      _modelPath = file.path;
    });
  }

  void _wireServiceStreams() {
    final service = FlutterBackgroundService();
    _logSub = service.on('log').listen((event) {
      if (event == null || !mounted) return;
      setState(() => _entries.add(LogEntry.fromJson(event)));
      _scrollToEnd();
    });
    _statusSub = service.on('status').listen((event) {
      if (event == null || !mounted) return;
      setState(() => _status = AgentStatus.fromJson(event));
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  bool get _isRunning =>
      _status.loopState == LoopRunState.running ||
      _status.loopState == LoopRunState.waitingForApproval ||
      _status.loopState == LoopRunState.waitingForHuman;

  Future<void> _sendTask() async {
    final task = _taskController.text.trim();
    if (task.isEmpty) return;
    if (!_modelPresent) {
      _showSnack('No model found at $_modelPath. Copy the Q4_K_M gguf there first.');
      return;
    }

    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
    service.invoke('startTask', {'task': task});
    _taskController.clear();
    setState(() {}); // reflect the (soon-to-arrive) running state promptly
  }

  void _stopAgent() {
    FlutterBackgroundService().invoke('stopLoop');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _statusSub?.cancel();
    _taskController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claco'),
        actions: [ModelStatusChip(state: _status.modelState)],
      ),
      body: Column(
        children: [
          if (!_modelPresent)
            MaterialBanner(
              content: Text('No model found. Place a Qwen2.5-Coder-1.5B-Instruct '
                  'Q4_K_M .gguf file at:\n$_modelPath'),
              actions: [
                TextButton(onPressed: _checkModel, child: const Text('Re-check')),
              ],
            ),
          if (_status.loopState == LoopRunState.waitingForApproval ||
              _status.loopState == LoopRunState.waitingForHuman)
            Container(
              width: double.infinity,
              color: Colors.orange.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _status.loopState == LoopRunState.waitingForApproval
                    ? 'Waiting for your approval: ${_status.pendingApprovalSummary ?? ''}\n'
                        'Respond from the notification.'
                    : 'The agent is asking: ${_status.pendingApprovalSummary ?? ''}\n'
                        'Reply from the notification.',
              ),
            ),
          Expanded(
            child: AgentLogView(entries: _entries, scrollController: _scrollController),
          ),
          const Divider(height: 1),
          TaskInputBar(
            controller: _taskController,
            isRunning: _isRunning,
            onSend: _sendTask,
            onStop: _stopAgent,
          ),
        ],
      ),
    );
  }
}
