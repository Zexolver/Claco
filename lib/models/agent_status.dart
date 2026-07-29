enum ModelLoadState { unloaded, loading, loaded, error }

enum LoopRunState { idle, running, waitingForApproval, waitingForHuman, stopped }

/// Snapshot of background-loop state, mirrored to the UI isolate on every
/// change via `FlutterBackgroundService.invoke('status', ...)`.
class AgentStatus {
  final ModelLoadState modelState;
  final LoopRunState loopState;
  final String? currentTask;
  final String? pendingApprovalSummary;

  const AgentStatus({
    this.modelState = ModelLoadState.unloaded,
    this.loopState = LoopRunState.idle,
    this.currentTask,
    this.pendingApprovalSummary,
  });

  AgentStatus copyWith({
    ModelLoadState? modelState,
    LoopRunState? loopState,
    String? currentTask,
    String? pendingApprovalSummary,
    bool clearTask = false,
    bool clearApproval = false,
  }) {
    return AgentStatus(
      modelState: modelState ?? this.modelState,
      loopState: loopState ?? this.loopState,
      currentTask: clearTask ? null : (currentTask ?? this.currentTask),
      pendingApprovalSummary: clearApproval
          ? null
          : (pendingApprovalSummary ?? this.pendingApprovalSummary),
    );
  }

  Map<String, dynamic> toJson() => {
        'modelState': modelState.name,
        'loopState': loopState.name,
        'currentTask': currentTask,
        'pendingApprovalSummary': pendingApprovalSummary,
      };

  factory AgentStatus.fromJson(Map<String, dynamic> json) => AgentStatus(
        modelState: ModelLoadState.values.firstWhere(
          (s) => s.name == json['modelState'],
          orElse: () => ModelLoadState.unloaded,
        ),
        loopState: LoopRunState.values.firstWhere(
          (s) => s.name == json['loopState'],
          orElse: () => LoopRunState.idle,
        ),
        currentTask: json['currentTask'] as String?,
        pendingApprovalSummary: json['pendingApprovalSummary'] as String?,
      );
}
