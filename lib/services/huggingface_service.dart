import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/hf_model.dart';

/// Lets the user fetch the model onto the device instead of sideloading it
/// by hand: search the Hugging Face Hub, list only the `.gguf` files in a
/// repo (the one format `flutter_llama` can load), and stream one down.
///
/// Uses the Hub's public, unauthenticated REST API — fine for public
/// repos, which is all this app ever browses.
class HuggingFaceService {
  HuggingFaceService._();
  static final HuggingFaceService instance = HuggingFaceService._();

  static const String _apiBase = 'https://huggingface.co/api/models';
  static const String _hubBase = 'https://huggingface.co';

  /// The exact model CLAUDE.md specifies — shown as the one-tap default so
  /// most users never need to touch the search UI.
  static const String recommendedRepoId =
      'Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF';
  static const String recommendedFile =
      'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf';
  static const String recommendedLabel = 'Qwen2.5-Coder-1.5B-Instruct (Q4_K_M)';

  Future<List<HfModelSummary>> searchModels(String query) async {
    final uri = Uri.parse(_apiBase).replace(queryParameters: {
      'search': query,
      'filter': 'gguf',
      'limit': '25',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException('Hugging Face search failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => HfModelSummary.fromJson(e as Map<String, dynamic>))
        .where((m) => m.repoId.isNotEmpty)
        .toList();
  }

  /// Lists every `.gguf` file in [repoId], descending into subfolders
  /// (many quantization repos group files under e.g. `Q4_K_M/`) up to
  /// [maxDepth] levels so this can't spiral into unbounded API calls.
  Future<List<HfGgufFile>> listGgufFiles(String repoId,
      {int maxDepth = 2}) async {
    final results = <HfGgufFile>[];
    await _walkTree(repoId, '', results, maxDepth);
    results.sort((a, b) => a.path.compareTo(b.path));
    return results;
  }

  Future<void> _walkTree(
    String repoId,
    String subPath,
    List<HfGgufFile> results,
    int depthRemaining,
  ) async {
    final treePath = subPath.isEmpty ? 'main' : 'main/$subPath';
    final uri = Uri.parse('$_apiBase/$repoId/tree/$treePath');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to list files for $repoId: ${response.statusCode}',
      );
    }
    final entries = jsonDecode(response.body) as List<dynamic>;
    for (final raw in entries) {
      final entry = raw as Map<String, dynamic>;
      final type = entry['type'] as String? ?? 'file';
      final path = entry['path'] as String? ?? '';
      if (type == 'directory') {
        if (depthRemaining > 0) {
          await _walkTree(repoId, path, results, depthRemaining - 1);
        }
        continue;
      }
      if (path.toLowerCase().endsWith('.gguf')) {
        results.add(HfGgufFile.fromTreeJson(entry));
      }
    }
  }

  /// Streams [file]'s path from [repoId] to [destPath], reporting bytes
  /// received via [onProgress]. Aborts mid-stream if [isCancelled] flips
  /// true, deleting the partial file.
  Future<void> downloadFile({
    required String repoId,
    required String filePath,
    required String destPath,
    required void Function(int received, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
    final uri =
        Uri.parse('$_hubBase/$repoId/resolve/main/$encodedPath?download=true');

    final client = http.Client();
    final destFile = File(destPath);
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;

      await destFile.parent.create(recursive: true);
      final sink = destFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (isCancelled?.call() ?? false) {
            throw const _DownloadCancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
    } catch (e) {
      if (destFile.existsSync()) {
        await destFile.delete();
      }
      rethrow;
    } finally {
      client.close();
    }
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
  @override
  String toString() => 'Download cancelled';
}
