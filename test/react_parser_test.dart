import 'package:flutter_test/flutter_test.dart';

import 'package:claco/models/agent_tool.dart';
import 'package:claco/services/react_parser.dart';

void main() {
  group('ReactParser', () {
    test('parses a well-formed response', () {
      const raw = '<THOUGHT>I should check the notes file.</THOUGHT>'
          '<ACTION>read_file</ACTION>'
          '<PARAMS>notes.md</PARAMS>';

      final step = ReactParser.parse(raw);

      expect(step.isValid, isTrue);
      expect(step.thought, 'I should check the notes file.');
      expect(step.tool, AgentTool.readFile);
      expect(step.params, 'notes.md');
    });

    test('is tolerant of a missing closing PARAMS tag and trailing im_end', () {
      const raw = '<THOUGHT>Wrapping up.</THOUGHT>'
          '<ACTION>done</ACTION>'
          '<PARAMS>All good<|im_end|>';

      final step = ReactParser.parse(raw);

      expect(step.isValid, isTrue);
      expect(step.tool, AgentTool.done);
      expect(step.params, 'All good');
    });

    test('reports invalid when the action is unrecognized', () {
      const raw = '<THOUGHT>Hmm.</THOUGHT><ACTION>delete_everything</ACTION><PARAMS></PARAMS>';

      final step = ReactParser.parse(raw);

      expect(step.isValid, isFalse);
      expect(step.tool, isNull);
    });
  });

  group('AgentTool', () {
    test('flags write_file as risky and other tools as not', () {
      expect(AgentTool.writeFile.isRisky, isTrue);
      expect(AgentTool.readFile.isRisky, isFalse);
      expect(AgentTool.askHuman.isRisky, isFalse);
      expect(AgentTool.done.isRisky, isFalse);
    });
  });
}
