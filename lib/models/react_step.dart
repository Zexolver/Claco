import 'agent_tool.dart';

/// One parsed `<THOUGHT>/<ACTION>/<PARAMS>` reply from the model.
class ReactStep {
  final String thought;
  final AgentTool? tool;
  final String rawToolName;
  final String params;

  const ReactStep({
    required this.thought,
    required this.tool,
    required this.rawToolName,
    required this.params,
  });

  bool get isValid => tool != null;
}
