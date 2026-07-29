import 'dart:async';
import 'dart:io';

import 'package:flutter_llama/flutter_llama.dart';
import 'package:path_provider/path_provider.dart';

/// Thin wrapper around `flutter_llama` configured per CLAUDE.md section 3:
/// 2048-token context, ~4 threads, low temperature for strict tag output.
///
/// The model runs entirely on-device — nothing here ever touches the
/// network. The `.gguf` weights are too large to ship in the repo/APK, so
/// they must be sideloaded onto the device once (see assets/models/README.md)
/// before the agent can load.
class LlamaService {
  LlamaService._();
  static final LlamaService instance = LlamaService._();

  static const String modelFileName = 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf';
  static const int contextSize = 2048;
  static const int threadCount = 4;
  static const double temperature = 0.15;

  final FlutterLlama _llama = FlutterLlama.instance;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<String> _modelPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/models/$modelFileName';
  }

  /// Returns null if the model weights are present and loadable, otherwise
  /// a human-readable reason the UI can surface (e.g. "file not found").
  Future<String?> load() async {
    final path = await _modelPath();
    if (!File(path).existsSync()) {
      return 'Model not found at $path.\n'
          'Push the Q4_K_M GGUF file there first, e.g.:\n'
          'adb push qwen2.5-coder-1.5b-instruct-q4_k_m.gguf '
          '/sdcard/Android/data/com.pocketagent.app/files/models/';
    }

    try {
      final ok = await _llama.loadModel(
        LlamaConfig(
          modelPath: path,
          nThreads: threadCount,
          contextSize: contextSize,
          useGpu: false,
        ),
      );
      _loaded = ok;
      return ok ? null : 'flutter_llama.loadModel returned false';
    } catch (e) {
      _loaded = false;
      return 'Failed to load model: $e';
    }
  }

  /// Runs one generation turn and returns the full text once the model
  /// closes </PARAMS> (or hits [maxTokens]), rather than exposing the raw
  /// token stream — the ReAct loop only ever needs the completed turn.
  Future<String> generateTurn(String prompt, {int maxTokens = 300}) async {
    if (!_loaded) {
      throw StateError('LlamaService.generateTurn called before load()');
    }

    final buffer = StringBuffer();
    final stream = _llama.generateStream(
      GenerationParams(
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        stopSequences: const ['</PARAMS>', '<|im_end|>'],
      ),
    );

    await for (final token in stream) {
      buffer.write(token);
      if (buffer.toString().contains('</PARAMS>')) break;
    }
    return buffer.toString();
  }

  Future<void> unload() async {
    if (!_loaded) return;
    await _llama.unloadModel();
    _loaded = false;
  }
}
