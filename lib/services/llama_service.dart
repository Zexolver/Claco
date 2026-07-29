import 'dart:async';
import 'dart:io';

import 'package:flutter_llama/flutter_llama.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import 'huggingface_service.dart';

/// Thin wrapper around `flutter_llama` configured per CLAUDE.md section 3:
/// 2048-token context, ~4 threads, low temperature for strict tag output.
///
/// The ReAct loop itself runs entirely on-device — nothing here touches
/// the network during inference. The `.gguf` weights are too large to
/// ship in the repo/APK, so they're fetched once via [HuggingFaceService]
/// (see the in-app Model Manager) or sideloaded by hand.
class LlamaService {
  LlamaService._();
  static final LlamaService instance = LlamaService._();

  static const int contextSize = 2048;
  static const int threadCount = 4;
  static const double temperature = 0.15;

  final FlutterLlama _llama = FlutterLlama.instance;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// The file name of whichever model the user picked in the Model
  /// Manager, falling back to the CLAUDE.md-recommended default when
  /// nothing has been explicitly selected yet.
  Future<String> selectedModelFileName() async {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString(StorageKeys.selectedModelFile);
    if (selected == null || selected.isEmpty) {
      return HuggingFaceService.recommendedFile;
    }
    return selected;
  }

  Future<String> _modelPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final fileName = await selectedModelFileName();
    return '${docsDir.path}/models/$fileName';
  }

  /// GGUF files start with this 4-byte ASCII magic. A model that fails
  /// this check is corrupt or truncated (e.g. an interrupted download) —
  /// llama.cpp's native parser aborts the whole process on malformed
  /// input rather than returning a catchable error, so this must be
  /// caught here, before ever handing the file to the native loader.
  static const List<int> _ggufMagic = [0x47, 0x47, 0x55, 0x46]; // "GGUF"

  /// Below this, a file can't plausibly be a real quantized LLM — almost
  /// certainly a truncated or failed download.
  static const int _minPlausibleModelBytes = 50 * 1024 * 1024;

  /// Returns null if the model weights are present and loadable, otherwise
  /// a human-readable reason the UI can surface (e.g. "file not found").
  Future<String?> load() async {
    final path = await _modelPath();
    final file = File(path);
    if (!file.existsSync()) {
      return 'Model not found at $path.\n'
          'Open the Model Manager to download the recommended '
          '${HuggingFaceService.recommendedLabel} model, pick a different '
          'one from Hugging Face, or push a .gguf file there by hand.';
    }

    final sanityError = await _sanityCheck(file);
    if (sanityError != null) return sanityError;

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

  Future<String?> _sanityCheck(File file) async {
    final size = await file.length();
    if (size < _minPlausibleModelBytes) {
      return 'Model file at ${file.path} is only $size bytes — too small '
          'to be a real model. The download probably got interrupted; '
          'delete it and re-download from the Model Manager.';
    }

    final raf = await file.open();
    try {
      final header = await raf.read(4);
      if (header.length < 4 ||
          header[0] != _ggufMagic[0] ||
          header[1] != _ggufMagic[1] ||
          header[2] != _ggufMagic[2] ||
          header[3] != _ggufMagic[3]) {
        return 'File at ${file.path} is not a valid GGUF file (bad '
            'header). It may be corrupted or an interrupted download; '
            'delete it and re-download from the Model Manager.';
      }
    } finally {
      await raf.close();
    }
    return null;
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
