enum AgentStatus {
  idle,
  loadingModel,
  running,
  waitingApproval,
  waitingHuman,
  stopped,
}

/// Snapshot of the background loop's state, per spec 4.1.1
/// (current_task / workspace_state / is_waiting_for_approval).
///
/// Serialized to SharedPreferences so the UI isolate and the background
/// service isolate — which do not share memory — can both read it.
class AgentState {
  AgentState({
    required this.status,
    required this.currentTask,
    required this.workspaceState,
    required this.pendingTool,
    required this.pendingParams,
    required this.iteration,
  });

  factory AgentState.initial() => AgentState(
        status: AgentStatus.idle,
        currentTask: '',
        workspaceState: 'empty workspace',
        pendingTool: '',
        pendingParams: '',
        iteration: 0,
      );

  final AgentStatus status;
  final String currentTask;
  final String workspaceState;

  /// The wire name of the tool awaiting approval, empty when nothing is
  /// pending.
  final String pendingTool;
  final String pendingParams;
  final int iteration;

  bool get isWaitingForApproval => status == AgentStatus.waitingApproval;
  bool get isWaitingForHuman => status == AgentStatus.waitingHuman;

  AgentState copyWith({
    AgentStatus? status,
    String? currentTask,
    String? workspaceState,
    String? pendingTool,
    String? pendingParams,
    int? iteration,
  }) {
    return AgentState(
      status: status ?? this.status,
      currentTask: currentTask ?? this.currentTask,
      workspaceState: workspaceState ?? this.workspaceState,
      pendingTool: pendingTool ?? this.pendingTool,
      pendingParams: pendingParams ?? this.pendingParams,
      iteration: iteration ?? this.iteration,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'currentTask': currentTask,
        'workspaceState': workspaceState,
        'pendingTool': pendingTool,
        'pendingParams': pendingParams,
        'iteration': iteration,
      };

  factory AgentState.fromJson(Map<String, dynamic> json) => AgentState(
        status: AgentStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => AgentStatus.idle,
        ),
        currentTask: json['currentTask'] as String? ?? '',
        workspaceState: json['workspaceState'] as String? ?? 'empty workspace',
        pendingTool: json['pendingTool'] as String? ?? '',
        pendingParams: json['pendingParams'] as String? ?? '',
        iteration: json['iteration'] as int? ?? 0,
      );
}
