import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';

import '../core/agent_constants.dart';
import '../models/agent_status.dart';
import '../models/agent_tool.dart';
import '../models/log_entry.dart';
import 'approval_bridge.dart';
import 'llm_service.dart';
import 'notification_service.dart';
import 'react_parser.dart';
import 'storage_service.dart';
import 'tool_executor.dart';

/// The autonomous Reason/Act/Observe loop (spec 4.1), running inside the
/// `flutter_background_service` isolate so it keeps ticking while the app
/// is backgrounded or the screen is off.
///
/// A single running transcript (system prompt + task + alternating
/// assistant/observation turns) is fed back into the model each iteration.
/// The loop pauses -- without burning battery on polling faster than its
/// own cadence -- whenever it hits a RISKY tool or `ask_human`, resuming
/// only once [ApprovalBridge] reports a decision from the notification
/// action the user tapped.
class AgentLoopService {
  AgentLoopService(this._service)
      : _storage = StorageService(),
        _llm = LlmService() {
    _executor = ToolExecutor(_storage);
  }

  final ServiceInstance _service;
  final StorageService _storage;
  final LlmService _llm;
  late final ToolExecutor _executor;

  String _transcript = '';
  bool _running = false;
  bool _stopRequested = false;
  AgentStatus _status = const AgentStatus();

  bool get isRunning => _running;

  Future<void> start(String task) async {
    if (_running) {
      _log(LogEntryKind.system, 'Already running; ignoring new task until current one finishes or is stopped.');
      return;
    }

    _running = true;
    _stopRequested = false;
    await ApprovalBridge.reset();

    _setStatus(_status.copyWith(loopState: LoopRunState.running, currentTask: task));
    _log(LogEntryKind.system, 'Task assigned: $task');

    _transcript = AgentConstants.systemPrompt + AgentConstants.userTurn(task);

    final modelReady = await _ensureModelLoaded();
    if (!modelReady) {
      _log(LogEntryKind.error, 'Model file not found on device; cannot start the loop.');
      _running = false;
      _setStatus(_status.copyWith(loopState: LoopRunState.idle));
      return;
    }

    await _loop();
  }

  void stop() {
    _stopRequested = true;
    _log(LogEntryKind.system, 'Stop requested by user.');
  }

  Future<bool> _ensureModelLoaded() async {
    if (_llm.isLoaded) return true;
    if (!await _storage.isModelPresent) return false;

    _setStatus(_status.copyWith(modelState: ModelLoadState.loading));
    try {
      final file = await _storage.modelFile;
      await _llm.loadModel(file.path);
      _setStatus(_status.copyWith(modelState: ModelLoadState.loaded));
      return true;
    } catch (e) {
      _log(LogEntryKind.error, 'Failed to load model: $e');
      _setStatus(_status.copyWith(modelState: ModelLoadState.error));
      return false;
    }
  }

  Future<void> _loop() async {
    while (!_stopRequested) {
      final String reply;
      try {
        reply = await _llm.complete(_transcript);
      } catch (e) {
        _log(LogEntryKind.error, 'Inference error: $e');
        break;
      }

      _transcript += reply;
      final step = ReactParser.parse(reply);

      if (!step.isValid) {
        _log(LogEntryKind.error, 'Model output did not match the required <THOUGHT>/<ACTION>/<PARAMS> format.');
        _transcript += AgentConstants.observationTurn(
          'Your last response did not match the required format. '
          'Respond ONLY with <THOUGHT>...</THOUGHT><ACTION>...</ACTION><PARAMS>...</PARAMS>.',
        );
        if (!await _delay()) break;
        continue;
      }

      _log(LogEntryKind.thought, step.thought);
      _log(LogEntryKind.action, '${step.tool!.wireName}  ${step.params}');

      if (step.tool == AgentTool.done) {
        final summary = step.params.isEmpty ? 'Task complete.' : step.params;
        _log(LogEntryKind.done, summary);
        await NotificationService.showTaskComplete(summary);
        break;
      }

      if (step.tool == AgentTool.askHuman) {
        if (!await _handleAskHuman(step.params)) break;
        if (!await _delay()) break;
        continue;
      }

      if (step.tool!.isRisky) {
        final approved = await _handleApproval(step.tool!, step.params);
        if (approved == null) break; // stopped while waiting
        if (!approved) {
          _transcript += AgentConstants.observationTurn(
            'The user denied this action. Choose a different approach.',
          );
          if (!await _delay()) break;
          continue;
        }
      }

      final result = await _executor.execute(step.tool!, step.params);
      _log(LogEntryKind.observation, result.observation);
      _transcript += AgentConstants.observationTurn(result.observation);
      _transcript = _truncate(_transcript);

      if (!await _delay()) break;
    }

    _running = false;
    await NotificationService.cancelApprovalPrompts();
    _setStatus(_status.copyWith(
      loopState: _stopRequested ? LoopRunState.stopped : LoopRunState.idle,
      clearApproval: true,
    ));
  }

  Future<bool> _handleAskHuman(String question) async {
    _setStatus(_status.copyWith(loopState: LoopRunState.waitingForHuman, pendingApprovalSummary: question));
    _log(LogEntryKind.humanQuestion, question);
    await NotificationService.showAskHuman(question);

    final reply = await _pollUntilStopped(ApprovalBridge.consumeHumanReply);
    if (reply == null) return false; // stop was requested

    _log(LogEntryKind.humanReply, reply);
    _transcript += AgentConstants.observationTurn('Human replied: $reply');
    _setStatus(_status.copyWith(loopState: LoopRunState.running, clearApproval: true));
    return true;
  }

  /// Returns true if approved, false if denied, or null if the loop was
  /// stopped while waiting.
  Future<bool?> _handleApproval(AgentTool tool, String params) async {
    final summary = '${tool.wireName}: $params';
    _setStatus(_status.copyWith(loopState: LoopRunState.waitingForApproval, pendingApprovalSummary: summary));
    _log(LogEntryKind.approvalRequested, summary);
    await NotificationService.showApprovalRequest(toolName: tool.wireName, summary: params);

    final decision = await _pollUntilStopped(ApprovalBridge.consumeDecision);
    if (decision == null) return null;

    final approved = decision == 'approve';
    _log(LogEntryKind.approvalResolved, approved ? 'Approved by user.' : 'Denied by user.');
    _setStatus(_status.copyWith(loopState: LoopRunState.running, clearApproval: true));
    return approved;
  }

  /// Polls [poll] every 2s until it returns a non-null value or the loop is
  /// asked to stop.
  Future<T?> _pollUntilStopped<T>(Future<T?> Function() poll) async {
    while (!_stopRequested) {
      final value = await poll();
      if (value != null) return value;
      await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  /// Sleeps for the configured inter-iteration delay in short increments so
  /// a stop request lands promptly instead of after a full 10s wait.
  /// Returns false if a stop was requested during the delay.
  Future<bool> _delay() async {
    const step = Duration(milliseconds: 500);
    var elapsed = Duration.zero;
    while (elapsed < AgentConstants.loopDelay) {
      if (_stopRequested) return false;
      await Future.delayed(step);
      elapsed += step;
    }
    return !_stopRequested;
  }

  /// Keeps the transcript within a rough character budget so a long-running
  /// task doesn't overflow the model's 2048-token context window. The
  /// system prompt and original task are always preserved; only the
  /// oldest observation/assistant turns are dropped.
  String _truncate(String transcript) {
    const maxChars = 6000;
    if (transcript.length <= maxChars) return transcript;

    final head = AgentConstants.systemPrompt;
    final tail = transcript.substring(transcript.length - (maxChars - head.length));
    final cut = tail.indexOf('<|im_start|>');
    return head + (cut == -1 ? tail : tail.substring(cut));
  }

  void _log(LogEntryKind kind, String text) {
    final entry = LogEntry(kind: kind, text: text);
    _service.invoke('log', entry.toJson());
  }

  void _setStatus(AgentStatus status) {
    _status = status;
    _service.invoke('status', status.toJson());
    if (_service is AndroidServiceInstance) {
      (_service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: 'Claco Agent',
        content: _statusLine(status),
      );
    }
  }

  String _statusLine(AgentStatus status) {
    switch (status.loopState) {
      case LoopRunState.idle:
        return 'Idle';
      case LoopRunState.running:
        return 'Working on: ${status.currentTask ?? '-'}';
      case LoopRunState.waitingForApproval:
        return 'Waiting for approval: ${status.pendingApprovalSummary ?? ''}';
      case LoopRunState.waitingForHuman:
        return 'Waiting for your answer: ${status.pendingApprovalSummary ?? ''}';
      case LoopRunState.stopped:
        return 'Stopped';
    }
  }
}
