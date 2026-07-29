import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Sandbox for the `read_file` / `write_file` tools (spec 4.2). All paths
/// are resolved relative to a single workspace directory under app storage
/// so the agent can never read or write outside its sandbox.
class WorkspaceService {
  WorkspaceService._();
  static final WorkspaceService instance = WorkspaceService._();

  Directory? _workspaceDir;

  Future<Directory> _dir() async {
    if (_workspaceDir != null) return _workspaceDir!;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/workspace');
    await dir.create(recursive: true);
    _workspaceDir = dir;
    return dir;
  }

  /// Resolves [relativePath] under the workspace root, rejecting any path
  /// that would escape it (e.g. via `..`).
  Future<File> _resolve(String relativePath) async {
    final dir = await _dir();
    final normalized = p.normalize(p.join(dir.path, relativePath));
    if (!p.isWithin(dir.path, normalized) && normalized != dir.path) {
      throw ArgumentError('Path escapes workspace sandbox: $relativePath');
    }
    return File(normalized);
  }

  Future<String> readFile(String relativePath) async {
    try {
      final file = await _resolve(relativePath);
      if (!file.existsSync()) {
        return 'ERROR: file not found: $relativePath';
      }
      return file.readAsStringSync();
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  Future<String> writeFile(String relativePath, String contents) async {
    try {
      final file = await _resolve(relativePath);
      await file.create(recursive: true);
      await file.writeAsString(contents);
      return 'OK: wrote ${contents.length} chars to $relativePath';
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  /// Upper bound on a single download_resource fetch, so a stray huge file
  /// can't fill the device's storage or hang the loop for minutes.
  static const int _maxDownloadBytes = 50 * 1024 * 1024;

  /// Fetches [url] and saves it into the sandbox — the download_resource
  /// tool's implementation. Callers must check the Settings network-
  /// downloads toggle themselves before calling this; it always attempts
  /// the fetch. [destPath] defaults to the URL's own filename.
  Future<String> downloadResource(String url, {String? destPath}) async {
    final Uri uri;
    try {
      uri = Uri.parse(url.trim());
    } catch (_) {
      return 'ERROR: invalid URL: $url';
    }
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'ERROR: only http(s) URLs are supported: $url';
    }

    final relativePath = (destPath == null || destPath.trim().isEmpty)
        ? (p.basename(uri.path).isEmpty
            ? 'downloaded_resource'
            : p.basename(uri.path))
        : destPath.trim();

    File file;
    try {
      file = await _resolve(relativePath);
    } catch (e) {
      return 'ERROR: $e';
    }

    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return 'ERROR: download failed with HTTP ${response.statusCode}';
      }

      await file.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          if (received > _maxDownloadBytes) {
            throw StateError(
              'resource exceeds the ${_maxDownloadBytes ~/ (1024 * 1024)}MB download limit',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return 'OK: downloaded $received bytes to $relativePath';
    } catch (e) {
      if (file.existsSync()) await file.delete();
      return 'ERROR: $e';
    } finally {
      client.close();
    }
  }

  /// Short one-line description of workspace contents, fed back into the
  /// prompt as WORKSPACE_STATE.
  Future<String> describeState() async {
    final dir = await _dir();
    final entries = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: dir.path))
        .toList()
      ..sort();
    if (entries.isEmpty) return 'empty workspace';
    return 'files: ${entries.join(', ')}';
  }
}
