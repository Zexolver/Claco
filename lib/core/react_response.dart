import 'agent_tools.dart';

/// One parsed THOUGHT/ACTION/PARAMS turn from the model.
class ReactResponse {
  const ReactResponse({
    required this.thought,
    required this.tool,
    required this.rawAction,
    required this.params,
  });

  final String thought;

  /// Null when [rawAction] didn't match any known [AgentTool] — the caller
  /// treats that as a malformed turn and re-prompts rather than executing.
  final AgentTool? tool;
  final String rawAction;
  final String params;

  bool get isValid => tool != null;
}

/// Best-effort extractor for the fixed THOUGHT/ACTION/PARAMS XML format.
///
/// A 1.5B model at low temperature is disciplined but not perfect: it
/// occasionally omits a closing tag or trails extra text after </PARAMS>.
/// The regexes below are deliberately lenient (dot-all, non-greedy, tags
/// optional-close) so a near-miss still parses instead of stalling the loop.
class ReactResponseParser {
  ReactResponseParser._();

  static final RegExp _thoughtTag = RegExp(
    r'<THOUGHT>(.*?)(?:</THOUGHT>|<ACTION>|$)',
    dotAll: true,
  );
  static final RegExp _actionTag = RegExp(
    r'<ACTION>(.*?)(?:</ACTION>|<PARAMS>|$)',
    dotAll: true,
  );
  static final RegExp _paramsTag = RegExp(
    r'<PARAMS>(.*?)(?:</PARAMS>|<\|im_end\|>|$)',
    dotAll: true,
  );

  static ReactResponse parse(String modelOutput) {
    final thoughtMatch = _thoughtTag.firstMatch(modelOutput);
    final actionMatch = _actionTag.firstMatch(modelOutput);
    final paramsMatch = _paramsTag.firstMatch(modelOutput);

    final thought = (thoughtMatch?.group(1) ?? '').trim();
    final rawAction = (actionMatch?.group(1) ?? '').trim();
    final params = (paramsMatch?.group(1) ?? '').trim();

    return ReactResponse(
      thought: thought,
      tool: AgentTool.fromWireName(rawAction),
      rawAction: rawAction,
      params: params,
    );
  }

  /// Splits a write_file PARAMS blob into (path, contents) per
  /// [kWriteFileParamHint]'s convention: first line is the path.
  static (String path, String contents) splitWriteFileParams(String params) {
    final newlineIndex = params.indexOf('\n');
    if (newlineIndex == -1) return (params.trim(), '');
    final path = params.substring(0, newlineIndex).trim();
    final contents = params.substring(newlineIndex + 1);
    return (path, contents);
  }

  /// Splits a download_resource PARAMS blob into (url, destPath) per
  /// [kDownloadResourceParamHint]'s convention: first line is the URL,
  /// an optional second line is the save-as path.
  static (String url, String? destPath) splitDownloadResourceParams(
      String params) {
    final newlineIndex = params.indexOf('\n');
    if (newlineIndex == -1) return (params.trim(), null);
    final url = params.substring(0, newlineIndex).trim();
    final destPath = params.substring(newlineIndex + 1).trim();
    return (url, destPath.isEmpty ? null : destPath);
  }
}
