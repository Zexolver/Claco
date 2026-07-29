import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/agent_constants.dart';

/// Resolves on-device paths for the agent's sandboxed workspace, the model
/// file, and the Markdown "Second Brain", and provides the small set of file
/// operations the `read_file`/`write_file`/`write_brain`/`search_brain`
/// tools are built on.
///
/// The workspace is intentionally confined to a single app-private
/// directory: every path the agent is given is resolved *inside* it, so a
/// `write_file` action can never escape onto the rest of the device.
class StorageService {
  Directory? _workspaceDir;
  Directory? _modelDir;

  Future<Directory> get workspaceDir async {
    if (_workspaceDir != null) return _workspaceDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/workspace');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _workspaceDir = dir;
    return dir;
  }

  /// Uses app-specific *external* storage rather than the internal documents
  /// directory: it holds up to a multi-GB gguf model file just as well, and
  /// -- unlike internal storage -- is reachable with a plain
  /// `adb push` (no `run-as`/root), which is how the model gets onto the
  /// device in the first place since the app never downloads it itself.
  Future<Directory> get modelDir async {
    if (_modelDir != null) return _modelDir!;
    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _modelDir = dir;
    return dir;
  }

  Future<File> get modelFile async {
    final dir = await modelDir;
    return File('${dir.path}/${AgentConstants.modelFileName}');
  }

  Future<bool> get isModelPresent async => (await modelFile).exists();

  Future<File> get secondBrainFile async {
    final dir = await workspaceDir;
    final file = File('${dir.path}/${AgentConstants.secondBrainFileName}');
    if (!await file.exists()) {
      await file.writeAsString(
        '# Second Brain\n\n'
        'This file is the agent\'s persistent knowledge graph. Entries are '
        'appended by the `write_brain` tool and retrieved by `search_brain`.\n\n',
      );
    }
    return file;
  }

  /// Resolves [relativePath] to an absolute path inside the workspace,
  /// rejecting any attempt to escape it via `..` segments or an absolute
  /// path.
  Future<File> _resolveInWorkspace(String relativePath) async {
    final dir = await workspaceDir;
    final cleaned = relativePath.trim().replaceAll('\\', '/');
    if (cleaned.isEmpty || cleaned.startsWith('/') || cleaned.contains('..')) {
      throw ArgumentError('Refusing to access path outside workspace: $relativePath');
    }
    return File('${dir.path}/$cleaned');
  }

  Future<String> readFile(String relativePath) async {
    final file = await _resolveInWorkspace(relativePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', file.path);
    }
    return file.readAsString();
  }

  Future<void> writeFile(String relativePath, String content) async {
    final file = await _resolveInWorkspace(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<void> appendToBrain(String entry) async {
    final file = await secondBrainFile;
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString(
      '\n## $timestamp\n$entry\n',
      mode: FileMode.append,
    );
  }

  /// Simple case-insensitive line-based text search, per spec 4.2
  /// ("performs a simple text search").
  Future<String> searchBrain(String query) async {
    final file = await secondBrainFile;
    final lines = await file.readAsLines();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return 'No search query provided.';

    final matches = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(needle)) {
        matches.add(lines[i].trim());
      }
    }
    if (matches.isEmpty) return 'No matches found for "$query".';
    return matches.take(20).join('\n');
  }
}
