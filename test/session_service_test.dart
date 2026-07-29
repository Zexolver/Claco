import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagai/models/agent_state.dart';
import 'package:pagai/models/log_entry.dart';
import 'package:pagai/services/session_service.dart';

void main() {
  final sessions = SessionService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('createSession adds it to the list and makes it active', () async {
    final meta = await sessions.createSession();

    final list = await sessions.listSessions();
    expect(list.map((s) => s.id), contains(meta.id));
    expect(await sessions.getActiveSessionId(), meta.id);
  });

  test('new sessions start with empty state and log', () async {
    final meta = await sessions.createSession();

    final state = await sessions.loadState(meta.id);
    final log = await sessions.loadLog(meta.id);

    expect(state.currentTask, isEmpty);
    expect(state.status, AgentStatus.idle);
    expect(log, isEmpty);
  });

  test('touchSession auto-titles a still-default chat from its first task',
      () async {
    final meta = await sessions.createSession();
    expect(meta.title, 'New chat');

    await sessions.touchSession(meta.id,
        autoTitleFromTask: 'Refactor the parser');

    final list = await sessions.listSessions();
    final updated = list.firstWhere((s) => s.id == meta.id);
    expect(updated.title, 'Refactor the parser');
  });

  test('touchSession does not overwrite a manually renamed chat', () async {
    final meta = await sessions.createSession();
    await sessions.renameSession(meta.id, 'My custom title');

    await sessions.touchSession(meta.id, autoTitleFromTask: 'Some new task');

    final list = await sessions.listSessions();
    final updated = list.firstWhere((s) => s.id == meta.id);
    expect(updated.title, 'My custom title');
  });

  test('appendLog accumulates entries per session without mixing others',
      () async {
    final a = await sessions.createSession();
    final b = await sessions.createSession();
    final prefs = await SharedPreferences.getInstance();

    await sessions.appendLog(
        prefs, a.id, LogEntry(kind: LogKind.system, text: 'in A'));
    await sessions.appendLog(
        prefs, b.id, LogEntry(kind: LogKind.system, text: 'in B'));

    final logA = sessions.loadLogWith(prefs, a.id);
    final logB = sessions.loadLogWith(prefs, b.id);
    expect(logA.single.text, 'in A');
    expect(logB.single.text, 'in B');
  });

  test('deleteSession removes it from the list and clears its data', () async {
    final meta = await sessions.createSession();
    final prefs = await SharedPreferences.getInstance();
    await sessions.appendLog(
        prefs, meta.id, LogEntry(kind: LogKind.system, text: 'hi'));

    await sessions.deleteSession(meta.id);

    final list = await sessions.listSessions();
    expect(list.map((s) => s.id), isNot(contains(meta.id)));
    expect(await sessions.loadLog(meta.id), isEmpty);
  });
}
