/// SharedPreferences keys shared between the UI isolate and the background
/// service isolate. SharedPreferences (backed by a plain file on Android)
/// is the IPC mechanism here because the notification-action callback,
/// the background service, and the UI all run in separate isolates/engines
/// that cannot pass Dart objects directly.
class StorageKeys {
  StorageKeys._();

  static const agentState = 'pocket_agent.state';
  static const agentLog = 'pocket_agent.log'; // JSON list of LogEntry
  static const newTask = 'pocket_agent.new_task';

  /// 'approve' | 'deny' | '' (empty = no decision yet).
  static const approvalDecision = 'pocket_agent.approval_decision';

  /// Free-text reply to an ask_human pause.
  static const humanReply = 'pocket_agent.human_reply';

  /// Set by the UI's stop button; the loop polls this and exits.
  static const stopRequested = 'pocket_agent.stop_requested';

  /// bool: whether the background isolate successfully loaded the GGUF
  /// model. The UI polls this to render the app-bar Loaded/Unloaded status.
  static const modelLoaded = 'pocket_agent.model_loaded';
}
