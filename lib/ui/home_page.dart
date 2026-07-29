import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/agent_state.dart';
import '../models/log_entry.dart';
import 'widgets/agent_log_view.dart';
import 'widgets/approval_banner.dart';
import 'widgets/task_input_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = FlutterBackgroundService();
  Timer? _pollTimer;

  AgentState _state = AgentState.initial();
  List<LogEntry> _log = [];
  bool _modelLoaded = false;
  bool _serviceRunning = false;

  @override
  void initState() {
    super.initState();
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

    AgentState state = _state;
    final rawState = prefs.getString(StorageKeys.agentState);
    if (rawState != null) {
      try {
        state =
            AgentState.fromJson(jsonDecode(rawState) as Map<String, dynamic>);
      } catch (_) {}
    }

    List<LogEntry> log = _log;
    final rawLog = prefs.getString(StorageKeys.agentLog);
    if (rawLog != null) {
      try {
        final decoded = jsonDecode(rawLog) as List<dynamic>;
        log = decoded
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _state = state;
      _log = log;
      _modelLoaded = prefs.getBool(StorageKeys.modelLoaded) ?? false;
      _serviceRunning = running;
    });
  }

  Future<void> _assignTask(String task) async {
    if (!_serviceRunning) {
      _service.startService();
      // Give the isolate a moment to spin up before it can receive events.
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _service.invoke('setTask', {'task': task});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Agent'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Chip(
              avatar: Icon(
                _modelLoaded ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: _modelLoaded ? Colors.greenAccent : Colors.white54,
              ),
              label: Text(_modelLoaded ? 'Loaded' : 'Unloaded'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            tooltip: 'Stop agent',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: _serviceRunning ? _stopAgent : null,
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
