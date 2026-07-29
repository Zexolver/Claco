/// Tuning + prompt constants from the project spec (section 3 and 5).
/// Keep these centralized: the system prompt format is load-bearing for the
/// regex-based parser in `react_parser.dart`, so the two must stay in sync.
class AgentConstants {
  AgentConstants._();

  static const int contextWindow = 2048;
  static const int inferenceThreads = 4;
  static const double temperature = 0.15;

  /// Delay enforced between ReAct loop iterations to avoid thermal
  /// throttling and battery drain on mobile ARM cores (spec 4.1.4).
  static const Duration loopDelay = Duration(seconds: 10);

  static const String modelFileName = 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf';
  static const String secondBrainFileName = 'knowledge_graph.md';

  static const String systemPrompt = '''
<|im_start|>system
You are a background AI coding agent running on an Android device.
Your goal is to complete the user's task. You have access to a "Second Brain" directory to store and retrieve knowledge.

You MUST respond ONLY in the following format:
<THOUGHT>Explain what you need to do next</THOUGHT>
<ACTION>Choose ONE: read_file, write_file, search_brain, write_brain, ask_human, done</ACTION>
<PARAMS>The file path, search query, or text to write</PARAMS>
<|im_end|>
''';

  static String userTurn(String task) => '<|im_start|>user\n$task<|im_end|>\n<|im_start|>assistant\n';

  static String observationTurn(String observation) =>
      '<|im_start|>user\nOBSERVATION: $observation<|im_end|>\n<|im_start|>assistant\n';
}
