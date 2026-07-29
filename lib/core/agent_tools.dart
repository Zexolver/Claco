/// The fixed set of actions the agent may choose in an <ACTION> tag.
///
/// Kept as plain strings (not just an enum) because the source of truth is
/// literally what the 1.5B model types out — it must round-trip exactly
/// against [AgentTool.values.map((t) => t.wireName)].
enum AgentTool {
  readFile('read_file'),
  writeFile('write_file'),
  searchBrain('search_brain'),
  writeBrain('write_brain'),
  askHuman('ask_human'),
  done('done');

  const AgentTool(this.wireName);

  final String wireName;

  static AgentTool? fromWireName(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final tool in AgentTool.values) {
      if (tool.wireName == normalized) return tool;
    }
    return null;
  }

  /// Actions that must pause the loop and page the human before executing,
  /// per spec section 4.3 (destructive / irreversible workspace writes).
  bool get isRisky => this == AgentTool.writeFile;

  /// Actions that always pause the loop regardless of risk, because they
  /// require information only the human has.
  bool get alwaysPauses => this == AgentTool.askHuman;
}
