/// One repo returned by the Hugging Face Hub model-search API.
class HfModelSummary {
  const HfModelSummary({
    required this.repoId,
    required this.downloads,
    required this.likes,
  });

  final String repoId;
  final int downloads;
  final int likes;

  factory HfModelSummary.fromJson(Map<String, dynamic> json) => HfModelSummary(
        repoId: json['id'] as String? ?? json['modelId'] as String? ?? '',
        downloads: (json['downloads'] as num?)?.toInt() ?? 0,
        likes: (json['likes'] as num?)?.toInt() ?? 0,
      );
}

/// One `.gguf` file inside a Hugging Face repo, from the repo tree API.
///
/// Only `.gguf` files are ever surfaced by [HuggingFaceService] — that's
/// the one format `flutter_llama` (llama.cpp) can load, so nothing else
/// is a legal choice for this app.
class HfGgufFile {
  const HfGgufFile({
    required this.path,
    required this.sizeBytes,
  });

  final String path;
  final int sizeBytes;

  factory HfGgufFile.fromTreeJson(Map<String, dynamic> json) => HfGgufFile(
        path: json['path'] as String? ?? '',
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      );

  String get readableSize {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = sizeBytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
