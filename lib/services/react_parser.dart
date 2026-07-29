import '../models/agent_tool.dart';
import '../models/react_step.dart';

/// Parses the model's rigid `<THOUGHT>/<ACTION>/<PARAMS>` output format
/// (spec 4.1.3 / 5). Deliberately tolerant of a 1.5B model's rough edges:
/// missing closing tags, stray whitespace, or `<|im_end|>` leaking into the
/// last tag are all handled rather than treated as hard failures.
class ReactParser {
  static final RegExp _thoughtRe = RegExp(
    r'<THOUGHT>(.*?)(?:</THOUGHT>|<ACTION>|$)',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _actionRe = RegExp(
    r'<ACTION>(.*?)(?:</ACTION>|<PARAMS>|$)',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _paramsRe = RegExp(
    r'<PARAMS>(.*?)(?:</PARAMS>|<\|im_end\|>|$)',
    dotAll: true,
    caseSensitive: false,
  );

  static ReactStep parse(String raw) {
    final thoughtMatch = _thoughtRe.firstMatch(raw);
    final actionMatch = _actionRe.firstMatch(raw);
    final paramsMatch = _paramsRe.firstMatch(raw);

    final thought = _clean(thoughtMatch?.group(1));
    final rawAction = _clean(actionMatch?.group(1));
    final params = _clean(paramsMatch?.group(1));

    return ReactStep(
      thought: thought,
      tool: AgentTool.fromWire(rawAction),
      rawToolName: rawAction,
      params: params,
    );
  }

  static String _clean(String? s) {
    if (s == null) return '';
    return s.replaceAll('<|im_end|>', '').trim();
  }
}
