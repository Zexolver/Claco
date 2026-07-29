import 'package:flutter_test/flutter_test.dart';
import 'package:pagai/models/hf_model.dart';
import 'package:pagai/services/huggingface_service.dart';

void main() {
  group('HfModelSummary', () {
    test('parses a search-result entry', () {
      final model = HfModelSummary.fromJson({
        'id': 'Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF',
        'downloads': 12345,
        'likes': 42,
      });

      expect(model.repoId, 'Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF');
      expect(model.downloads, 12345);
      expect(model.likes, 42);
    });

    test('falls back to modelId when id is absent', () {
      final model = HfModelSummary.fromJson({'modelId': 'org/name'});
      expect(model.repoId, 'org/name');
      expect(model.downloads, 0);
    });
  });

  group('HfGgufFile', () {
    test('formats human-readable sizes', () {
      expect(
        const HfGgufFile(path: 'a.gguf', sizeBytes: 500).readableSize,
        '500.0 B',
      );
      expect(
        const HfGgufFile(
          path: 'a.gguf',
          sizeBytes: 3 * 1024 * 1024,
        ).readableSize,
        '3.0 MB',
      );
      expect(
        const HfGgufFile(
          path: 'a.gguf',
          sizeBytes: 2 * 1024 * 1024 * 1024,
        ).readableSize,
        '2.0 GB',
      );
    });
  });

  group('HuggingFaceService recommended defaults', () {
    test('recommended file is a .gguf per CLAUDE.md', () {
      expect(
        HuggingFaceService.recommendedFile.toLowerCase().endsWith('.gguf'),
        isTrue,
      );
      expect(
        HuggingFaceService.recommendedRepoId,
        contains('Qwen2.5-Coder-1.5B'),
      );
    });
  });
}
