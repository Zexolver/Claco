/// The fixed set of tools the agent may choose in the `<ACTION>` tag of a
/// ReAct step. Kept as a small closed enum (rather than a JSON schema)
/// because the 1.5B model can only reliably reproduce a short fixed
/// vocabulary of action names.
enum AgentTool {
  readFile,
  writeFile,
  writeBrain,
  searchBrain,
  askHuman,
  done;

  static AgentTool? fromWire(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'read_file':
        return AgentTool.readFile;
      case 'write_file':
        return AgentTool.writeFile;
      case 'write_brain':
        return AgentTool.writeBrain;
      case 'search_brain':
        return AgentTool.searchBrain;
      case 'ask_human':
        return AgentTool.askHuman;
      case 'done':
        return AgentTool.done;
      default:
        return null;
    }
  }

  String get wireName {
    switch (this) {
      case AgentTool.readFile:
        return 'read_file';
      case AgentTool.writeFile:
        return 'write_file';
      case AgentTool.writeBrain:
        return 'write_brain';
      case AgentTool.searchBrain:
        return 'search_brain';
      case AgentTool.askHuman:
        return 'ask_human';
      case AgentTool.done:
        return 'done';
    }
  }

  /// Risky tools pause the loop and require an explicit Approve/Deny via a
  /// system notification before they execute (spec 4.3). `ask_human` also
  /// pauses the loop, but as a question rather than an approval gate.
  bool get isRisky => this == AgentTool.writeFile;
}
