import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent_tools.dart';
import '../core/prompt.dart';
import '../core/react_response.dart';
import '../core/storage_keys.dart';
import '../models/agent_state.dart';
import '../models/log_entry.dart';
import 'brain_service.dart';
import 'llama_service.dart';
import 'notification_service.dart';
import 'session_service.dart';
import 'settings_service.dart';
import 'workspace_service.dart';

/// Iteration delay enforced between every loop pass (spec 4.1.4) to avoid
/// thermal throttling / battery drain from back-to-back CPU inference.
const Duration kLoopDelay = Duration(seconds: 10);

/// Shorter poll interval used only while paused for human input — this
/// does not run inference, so it doesn't need the full loop delay.
const Duration kApprovalPollInterval = Duration(seconds: 2);

const String _notificationChannelId = 'pocket_agent_foreground';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      initialNotificationTitle: 'Pagai',
      initialNotificationContent: 'Idle',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifications = NotificationService.instance;
  await notifications.init();
  final sessions = SessionService.instance;

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Pagai',
      content: 'Idle',
    );
  }

  var stopRequested = false;

  // Which chat the loop is actively working, or null when idle. Only one
  // chat's agent can run at a time — one model, one service — so a
  // setTask for a different chat while this is non-null gets rejected
  // (see the 'setTask' listener below).
  String? runningSessionId;

  service.on('stopLoop').listen((event) async {
    stopRequested = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.stopRequested, true);

    final sid = runningSessionId;
    if (sid != null) {
      final state = sessions
          .loadStateWith(prefs, sid)
          .copyWith(status: AgentStatus.stopped);
      await sessions.persistState(prefs, sid, state);
    }
    runningSessionId = null;
    await prefs.remove(StorageKeys.runningSessionId);
  });

  service.on('setTask').listen((event) async {
    final task = event?['task'] as String? ?? '';
    final sessionId = event?['sessionId'] as String? ?? '';
    if (task.isEmpty || sessionId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    if (runningSessionId != null && runningSessionId != sessionId) {
      await sessions.appendLog(
        prefs,
        sessionId,
        LogEntry(
          kind: LogKind.error,
          text: 'Agent is busy in another chat. Stop it there before '
              'starting a task in this one.',
        ),
      );
      return;
    }

    await prefs.setBool(StorageKeys.stopRequested, false);
    stopRequested = false;

    var state = sessions.loadStateWith(prefs, sessionId);
    state = state.copyWith(
      status: AgentStatus.running,
      currentTask: task,
      pendingTool: '',
      pendingParams: '',
      iteration: 0,
    );
    await sessions.persistState(prefs, sessionId, state);
    await sessions.appendLog(
      prefs,
      sessionId,
      LogEntry(kind: LogKind.system, text: 'New task assigned: $task'),
    );
    await sessions.touchSession(sessionId, autoTitleFromTask: task);

    runningSessionId = sessionId;
    await prefs.setString(StorageKeys.runningSessionId, sessionId);
  });

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(StorageKeys.stopRequested, false);
  await prefs.remove(StorageKeys.runningSessionId);

  final llama = LlamaService.instance;
  final loadError = await llama.load();
  await prefs.setBool(StorageKeys.modelLoaded, loadError == null);
  var currentModelFileName = await llama.selectedModelFileName();

  // Fired by the Model Manager after the user downloads/picks a
  // different .gguf file, so a running loop doesn't need a full app
  // restart to pick it up.
  service.on('reloadModel').listen((event) async {
    final newFileName = await llama.selectedModelFileName();
    if (newFileName == currentModelFileName && llama.isLoaded) return;

    await llama.unload();
    final err = await llama.load();
    currentModelFileName = newFileName;
    final reloadPrefs = await SharedPreferences.getInstance();
    await reloadPrefs.setBool(StorageKeys.modelLoaded, err == null);
  });

  String lastObservation = 'none yet';

  while (!stopRequested) {
    final freshPrefs = await SharedPreferences.getInstance();
    stopRequested = freshPrefs.getBool(StorageKeys.stopRequested) ?? false;
    if (stopRequested) break;

    final sessionId = runningSessionId;
    if (sessionId == null || !llama.isLoaded) {
      await Future.delayed(kLoopDelay);
      continue;
    }

    var state = sessions.loadStateWith(freshPrefs, sessionId);

    _setForegroundText(service, 'Thinking about: ${state.currentTask}');

    final prompt = buildTurnPrompt(
      task: state.currentTask,
      workspaceState: state.workspaceState,
      lastObservation: lastObservation,
    );

    String rawOutput;
    try {
      rawOutput = await llama.generateTurn(prompt);
    } catch (e) {
      await sessions.appendLog(
        freshPrefs,
        sessionId,
        LogEntry(kind: LogKind.error, text: 'Inference failed: $e'),
      );
      await Future.delayed(kLoopDelay);
      continue;
    }

    final response = ReactResponseParser.parse(rawOutput);

    if (response.thought.isNotEmpty) {
      await sessions.appendLog(
        freshPrefs,
        sessionId,
        LogEntry(kind: LogKind.thought, text: response.thought),
      );
    }

    if (!response.isValid) {
      lastObservation =
          'Your last response could not be parsed. Respond ONLY with '
          '<THOUGHT>...</THOUGHT><ACTION>...</ACTION><PARAMS>...</PARAMS>.';
      await sessions.appendLog(
        freshPrefs,
        sessionId,
        LogEntry(
          kind: LogKind.error,
          text: 'Malformed response (raw action: "${response.rawAction}")',
        ),
      );
      await Future.delayed(kLoopDelay);
      continue;
    }

    final tool = response.tool!;
    await sessions.appendLog(
      freshPrefs,
      sessionId,
      LogEntry(
        kind: LogKind.action,
        text: '${tool.wireName}: ${response.params}',
      ),
    );

    if (tool == AgentTool.done) {
      await notifications.showDone(response.params);
      state = state.copyWith(status: AgentStatus.stopped);
      await sessions.persistState(freshPrefs, sessionId, state);
      _setForegroundText(service, 'Idle');
      runningSessionId = null;
      await freshPrefs.remove(StorageKeys.runningSessionId);
      lastObservation = 'none yet';
      continue;
    }

    final needsPause = tool.isRisky || tool.alwaysPauses;
    if (needsPause) {
      state = state.copyWith(
        status: tool.alwaysPauses
            ? AgentStatus.waitingHuman
            : AgentStatus.waitingApproval,
        pendingTool: tool.wireName,
        pendingParams: response.params,
      );
      await sessions.persistState(freshPrefs, sessionId, state);

      if (tool.alwaysPauses) {
        await notifications.showAskHuman(response.params);
      } else {
        await notifications.showApprovalRequest(
          tool: tool.wireName,
          params: response.params,
        );
      }
      _setForegroundText(service, 'Waiting for your input…');

      final outcome = await _waitForHumanDecision(
        tool: tool,
        checkStop: () => stopRequested,
      );
      await notifications.cancelApprovalRequest();
      if (outcome == null) {
        // Loop was stopped while paused.
        break;
      }
      lastObservation = outcome;
      await sessions.appendLog(
        freshPrefs,
        sessionId,
        LogEntry(kind: LogKind.observation, text: outcome),
      );

      state = state.copyWith(
        status: AgentStatus.running,
        pendingTool: '',
        pendingParams: '',
      );
    } else {
      final observation = await _execute(tool, response.params);
      lastObservation = observation;
      await sessions.appendLog(
        freshPrefs,
        sessionId,
        LogEntry(kind: LogKind.observation, text: observation),
      );
    }

    final workspaceState = await WorkspaceService.instance.describeState();
    state = state.copyWith(
      workspaceState: workspaceState,
      iteration: state.iteration + 1,
    );
    await sessions.persistState(freshPrefs, sessionId, state);
    _setForegroundText(service, 'Iteration ${state.iteration}');

    await Future.delayed(kLoopDelay);
  }

  if (service is AndroidServiceInstance) {
    service.stopSelf();
  }
}

Future<String> _execute(AgentTool tool, String params) async {
  switch (tool) {
    case AgentTool.readFile:
      return WorkspaceService.instance.readFile(params);
    case AgentTool.writeFile:
      final (path, contents) = ReactResponseParser.splitWriteFileParams(params);
      return WorkspaceService.instance.writeFile(path, contents);
    case AgentTool.searchBrain:
      return BrainService.instance.search(params);
    case AgentTool.writeBrain:
      return BrainService.instance.append(params);
    case AgentTool.downloadResource:
      final enabled = await SettingsService.instance.networkDownloadsEnabled();
      if (!enabled) {
        return 'ERROR: resource downloads are disabled in Settings '
            '("Allow the agent to download resources"). Try completing '
            'the task without it, or use ask_human to request it be '
            'turned on.';
      }
      final (url, destPath) =
          ReactResponseParser.splitDownloadResourceParams(params);
      return WorkspaceService.instance
          .downloadResource(url, destPath: destPath);
    case AgentTool.askHuman:
      return 'Waiting for human reply.';
    case AgentTool.done:
      return 'done';
  }
}

/// Blocks (via polling) until the paused action is resolved by the human,
/// or [checkStop] flips true. Returns the observation text to feed back
/// into the next prompt, or null if the loop should stop entirely.
Future<String?> _waitForHumanDecision({
  required AgentTool tool,
  required bool Function() checkStop,
}) async {
  while (true) {
    if (checkStop()) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(StorageKeys.stopRequested) ?? false) return null;

    if (tool.alwaysPauses) {
      final reply = prefs.getString(StorageKeys.humanReply);
      if (reply != null && reply.isNotEmpty) {
        await prefs.remove(StorageKeys.humanReply);
        return 'User replied: $reply';
      }
    } else {
      final decision = prefs.getString(StorageKeys.approvalDecision);
      if (decision == 'approve') {
        await prefs.remove(StorageKeys.approvalDecision);
        final sessionId = prefs.getString(StorageKeys.runningSessionId);
        if (sessionId == null) return 'Approved, but no running chat found.';
        return _resumeApprovedAction(prefs, sessionId);
      } else if (decision == 'deny') {
        await prefs.remove(StorageKeys.approvalDecision);
        return 'User denied the action.';
      }
    }
    await Future.delayed(kApprovalPollInterval);
  }
}

Future<String> _resumeApprovedAction(
    SharedPreferences prefs, String sessionId) async {
  final state = SessionService.instance.loadStateWith(prefs, sessionId);
  final tool = AgentTool.fromWireName(state.pendingTool);
  if (tool == null) return 'Approved, but no pending action found.';
  final result = await _execute(tool, state.pendingParams);
  return 'User approved. $result';
}

void _setForegroundText(ServiceInstance service, String text) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Pagai',
      content: text,
    );
  }
  service.invoke('statusUpdate', {'text': text});
}
