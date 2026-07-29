import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../core/agent_constants.dart';

/// Thin wrapper around `llama_cpp_dart`'s `Llama` binding, configured per
/// spec 3: a 2048-token context, ~4 CPU threads, and a low temperature to
/// keep the 1.5B model's output close to the rigid `<THOUGHT>/<ACTION>`
/// format the parser expects.
class LlmService {
  Llama? _llama;

  bool get isLoaded => _llama != null && !_llama!.isDisposed;

  Future<void> loadModel(String modelPath) async {
    unload();
    _llama = Llama(
      modelPath,
      contextParams: ContextParams()
        ..nCtx = AgentConstants.contextWindow
        ..nThreads = AgentConstants.inferenceThreads
        ..nThreadsBatch = AgentConstants.inferenceThreads,
      samplerParams: SamplerParams()..temp = AgentConstants.temperature,
      verbose: false,
    );
  }

  void unload() {
    _llama?.dispose();
    _llama = null;
  }

  /// Runs one ReAct turn: feeds [prompt] to the model and returns the full
  /// generated text once the model emits a stop marker or the response
  /// looks like a complete `<THOUGHT>...<PARAMS>...` triple.
  Future<String> complete(String prompt) async {
    final llama = _llama;
    if (llama == null) {
      throw StateError('Model is not loaded');
    }

    llama.setPrompt(prompt);

    final buffer = StringBuffer();
    await for (final token in llama.generateText()) {
      buffer.write(token);
      final text = buffer.toString();
      if (text.contains('<|im_end|>') || _looksComplete(text)) {
        break;
      }
    }
    return buffer.toString();
  }

  bool _looksComplete(String text) {
    final hasParamsOpen = text.contains('<PARAMS>');
    final hasParamsClose = text.contains('</PARAMS>');
    return hasParamsOpen && hasParamsClose;
  }
}
