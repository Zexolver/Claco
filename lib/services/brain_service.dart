import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The agent's "Second Brain" — a single markdown knowledge file it can
/// append to (`write_brain`) and grep (`search_brain`), per spec 4.2.
class BrainService {
  BrainService._();
  static final BrainService instance = BrainService._();

  static const String _fileName = 'knowledge_graph.md';

  Future<File> _file() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/second_brain');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$_fileName');
    if (!file.existsSync()) {
      await file.writeAsString('# Second Brain\n\n');
    }
    return file;
  }

  Future<String> append(String entry) async {
    final file = await _file();
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString(
      '\n## $timestamp\n$entry\n',
      mode: FileMode.append,
    );
    return 'OK: appended ${entry.length} chars to brain';
  }

  /// Simple case-insensitive line search — deliberately not a vector/
  /// embedding search, matching the spec's "simple text search" wording
  /// and the 1.5B model's inability to consume large ranked result sets.
  Future<String> search(String query) async {
    final file = await _file();
    final lines = await file.readAsLines();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return 'no query given';

    final matches = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(needle)) {
        matches.add('L${i + 1}: ${lines[i]}');
      }
    }
    if (matches.isEmpty) return 'no matches for "$query"';
    return matches.take(10).join('\n');
  }
}
