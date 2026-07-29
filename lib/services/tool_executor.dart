import '../models/agent_tool.dart';
import 'storage_service.dart';

/// Result of a single tool execution, fed back into the next prompt turn as
/// an `OBSERVATION:` (spec 4.1.2/4.1.3).
class ToolResult {
  final bool success;
  final String observation;

  const ToolResult(this.success, this.observation);
}

/// Executes the non-control-flow tools (`read_file`, `write_file`,
/// `write_brain`, `search_brain`) against the sandboxed workspace.
///
/// `ask_human` and `done` are control-flow actions handled directly by the
/// ReAct loop (they pause/terminate the loop rather than producing a plain
/// observation), so they are not dispatched through here.
class ToolExecutor {
  ToolExecutor(this._storage);

  final StorageService _storage;

  Future<ToolResult> execute(AgentTool tool, String params) async {
    try {
      switch (tool) {
        case AgentTool.readFile:
          final content = await _storage.readFile(params);
          return ToolResult(true, content);

        case AgentTool.writeFile:
          final parts = _splitPathAndContent(params);
          await _storage.writeFile(parts.$1, parts.$2);
          return ToolResult(true, 'Wrote ${parts.$2.length} chars to ${parts.$1}');

        case AgentTool.writeBrain:
          await _storage.appendToBrain(params);
          return const ToolResult(true, 'Saved to Second Brain.');

        case AgentTool.searchBrain:
          final result = await _storage.searchBrain(params);
          return ToolResult(true, result);

        case AgentTool.askHuman:
        case AgentTool.done:
          throw StateError('${tool.wireName} must be handled by the loop, not the executor');
      }
    } catch (e) {
      return ToolResult(false, 'ERROR: $e');
    }
  }

  /// `write_file` params are a single string in the rigid PARAMS tag. The
  /// model is expected to put the path on the first line and the file body
  /// on the rest, separated by `|||`, e.g. `notes.md|||# Notes\n...`. Falls
  /// back to treating the whole param as a path with empty content if the
  /// separator is missing, so a malformed response degrades gracefully
  /// instead of throwing.
  (String, String) _splitPathAndContent(String params) {
    const sep = '|||';
    final idx = params.indexOf(sep);
    if (idx == -1) return (params.trim(), '');
    final path = params.substring(0, idx).trim();
    final content = params.substring(idx + sep.length);
    return (path, content);
  }
}
