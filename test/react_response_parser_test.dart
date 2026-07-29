import 'package:flutter_test/flutter_test.dart';
import 'package:pagai/core/agent_tools.dart';
import 'package:pagai/core/react_response.dart';

void main() {
  group('ReactResponseParser', () {
    test('parses a well-formed turn', () {
      final response = ReactResponseParser.parse(
        '<THOUGHT>I should check the file</THOUGHT>'
        '<ACTION>read_file</ACTION>'
        '<PARAMS>notes.md</PARAMS>',
      );

      expect(response.thought, 'I should check the file');
      expect(response.tool, AgentTool.readFile);
      expect(response.params, 'notes.md');
      expect(response.isValid, isTrue);
    });

    test('is lenient about a missing closing tag', () {
      final response = ReactResponseParser.parse(
        '<THOUGHT>Wrapping up<ACTION>done</ACTION><PARAMS>All set</PARAMS>',
      );

      expect(response.thought, 'Wrapping up');
      expect(response.tool, AgentTool.done);
      expect(response.params, 'All set');
    });

    test('flags an unrecognized action as invalid', () {
      final response = ReactResponseParser.parse(
        '<THOUGHT>hmm</THOUGHT><ACTION>delete_everything</ACTION><PARAMS></PARAMS>',
      );

      expect(response.tool, isNull);
      expect(response.isValid, isFalse);
    });

    test('splits write_file params into path and contents', () {
      final (path, contents) = ReactResponseParser.splitWriteFileParams(
        'notes.md\nline one\nline two',
      );

      expect(path, 'notes.md');
      expect(contents, 'line one\nline two');
    });

    test('splits download_resource params into url and optional destPath', () {
      final (url, destPath) = ReactResponseParser.splitDownloadResourceParams(
        'https://example.com/lib.tar.gz\nvendor/lib.tar.gz',
      );
      expect(url, 'https://example.com/lib.tar.gz');
      expect(destPath, 'vendor/lib.tar.gz');

      final (urlOnly, noDest) = ReactResponseParser.splitDownloadResourceParams(
        'https://example.com/lib.tar.gz',
      );
      expect(urlOnly, 'https://example.com/lib.tar.gz');
      expect(noDest, isNull);
    });
  });

  group('AgentTool', () {
    test('write_file is risky, ask_human always pauses', () {
      expect(AgentTool.writeFile.isRisky, isTrue);
      expect(AgentTool.readFile.isRisky, isFalse);
      expect(AgentTool.askHuman.alwaysPauses, isTrue);
      expect(AgentTool.done.alwaysPauses, isFalse);
    });

    test('download_resource is settings-gated, not a risky per-call approval',
        () {
      expect(AgentTool.downloadResource.isRisky, isFalse);
      expect(AgentTool.downloadResource.alwaysPauses, isFalse);
    });

    test('download_resource round-trips through fromWireName', () {
      expect(AgentTool.fromWireName('download_resource'),
          AgentTool.downloadResource);
    });

    test('fromWireName is case-insensitive and rejects unknown tools', () {
      expect(AgentTool.fromWireName('WRITE_BRAIN'), AgentTool.writeBrain);
      expect(AgentTool.fromWireName('nonsense'), isNull);
    });
  });
}
