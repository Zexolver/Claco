/// System prompt fed to Qwen2.5-Coder-1.5B on every loop iteration.
///
/// This is the exact structure mandated by the project spec (CLAUDE.md
/// section 5) — a 1.5B model can't reliably follow a JSON tool-calling
/// schema, so the format is a rigid three-tag XML block instead. Do not
/// "improve" the wording without re-validating that the model still emits
/// well-formed tags; small phrasing changes measurably change how often a
/// 1.5B model drifts out of format.
const String kAgentSystemPrompt = '''
<|im_start|>system
You are a background AI coding agent running on an Android device.
Your goal is to complete the user's task. You have access to a "Second Brain" directory to store and retrieve knowledge.

You MUST respond ONLY in the following format:
<THOUGHT>Explain what you need to do next</THOUGHT>
<ACTION>Choose ONE: read_file, write_file, search_brain, write_brain, download_resource, ask_human, done</ACTION>
<PARAMS>The file path, search query, or text to write</PARAMS>
<|im_end|>''';

/// For [AgentTool.writeFile] the single free-text PARAMS slot has to carry
/// both a path and file contents. Convention: first line is the path,
/// everything after the first newline is the file body.
const String kWriteFileParamHint =
    'For write_file, PARAMS must be the file path on the first line, '
    'then a newline, then the full file contents.';

/// Same one-slot problem as write_file: download_resource needs a URL and
/// an optional destination path. Convention: first line is the URL,
/// second line (optional) is where to save it in the workspace.
const String kDownloadResourceParamHint =
    'For download_resource, PARAMS must be the http(s) URL on the first '
    'line, then optionally a second line with the workspace path to save '
    'it as (defaults to the URL\'s filename).';

String buildTurnPrompt({
  required String task,
  required String workspaceState,
  required String lastObservation,
}) {
  final buffer = StringBuffer()
    ..writeln(kAgentSystemPrompt)
    ..writeln('<|im_start|>user')
    ..writeln('CURRENT_TASK: $task')
    ..writeln('WORKSPACE_STATE: $workspaceState')
    ..writeln('LAST_OBSERVATION: $lastObservation')
    ..writeln(kWriteFileParamHint)
    ..writeln(kDownloadResourceParamHint)
    ..writeln('<|im_end|>')
    ..write('<|im_start|>assistant\n');
  return buffer.toString();
}
