/// SharedPreferences keys shared between the UI isolate and the background
/// service isolate. SharedPreferences (backed by a plain file on Android)
/// is the IPC mechanism here because the notification-action callback,
/// the background service, and the UI all run in separate isolates/engines
/// that cannot pass Dart objects directly.
class StorageKeys {
  StorageKeys._();

  /// JSON list of [ChatSessionMeta] — the chat list's index. Each session's
  /// own state/log live under their own [sessionState]/[sessionLog] keys so
  /// switching chats never requires rewriting every other chat's history.
  static const sessionsIndex = 'pocket_agent.sessions_index';

  /// Which chat the UI currently has open.
  static const activeSessionId = 'pocket_agent.active_session_id';

  /// Which chat the background loop is actively working on, or null when
  /// idle. Only one chat's agent can run at a time (one model, one
  /// service), so other chats show a "busy" state until this clears.
  static const runningSessionId = 'pocket_agent.running_session_id';

  static String sessionState(String sessionId) =>
      'pocket_agent.session.$sessionId.state';
  static String sessionLog(String sessionId) =>
      'pocket_agent.session.$sessionId.log';

  /// 'approve' | 'deny' | '' (empty = no decision yet).
  static const approvalDecision = 'pocket_agent.approval_decision';

  /// Free-text reply to an ask_human pause.
  static const humanReply = 'pocket_agent.human_reply';

  /// Set by the UI's stop button; the loop polls this and exits.
  static const stopRequested = 'pocket_agent.stop_requested';

  /// bool: whether the background isolate successfully loaded the GGUF
  /// model. The UI polls this to render the app-bar Loaded/Unloaded status.
  static const modelLoaded = 'pocket_agent.model_loaded';

  /// Which model is currently selected, set by the Model Manager once a
  /// download finishes. Empty means "use the CLAUDE.md-recommended
  /// default" (see HuggingFaceService.recommendedRepoId/recommendedFile).
  static const selectedModelRepo = 'pocket_agent.selected_model_repo';
  static const selectedModelFile = 'pocket_agent.selected_model_file';

  /// bool, default true: whether the app may reach the network to fetch
  /// resources (currently just Hugging Face model downloads). Off for
  /// fully-offline use or limited data plans — set in Settings.
  static const networkDownloadsEnabled =
      'pocket_agent.network_downloads_enabled';
}
