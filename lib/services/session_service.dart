import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/agent_state.dart';
import '../models/chat_session.dart';
import '../models/log_entry.dart';

/// CRUD for the chat list (spec: multiple chats, not a single thread) plus
/// the per-session state/log that back each chat's transcript. Used from
/// both the UI isolate and the background service isolate — it's just
/// SharedPreferences reads/writes, safe from either side.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const int _maxLogEntriesPerSession = 300;

  Future<List<ChatSessionMeta>> listSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readIndex(prefs);
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  Future<ChatSessionMeta> createSession({String title = 'New chat'}) async {
    final prefs = await SharedPreferences.getInstance();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    final meta =
        ChatSessionMeta(id: id, title: title, createdAt: now, updatedAt: now);

    final sessions = await _readIndex(prefs);
    sessions.add(meta);
    await _writeIndex(prefs, sessions);

    await prefs.setString(
      StorageKeys.sessionState(id),
      jsonEncode(AgentState.initial().toJson()),
    );
    await prefs.setString(StorageKeys.sessionLog(id), jsonEncode(<dynamic>[]));
    await setActiveSessionId(id);
    return meta;
  }

  Future<void> deleteSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readIndex(prefs);
    sessions.removeWhere((s) => s.id == id);
    await _writeIndex(prefs, sessions);
    await prefs.remove(StorageKeys.sessionState(id));
    await prefs.remove(StorageKeys.sessionLog(id));

    if (prefs.getString(StorageKeys.activeSessionId) == id) {
      await prefs.remove(StorageKeys.activeSessionId);
    }
  }

  Future<void> renameSession(String id, String title) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readIndex(prefs);
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) return;
    sessions[index] = sessions[index].copyWith(title: title);
    await _writeIndex(prefs, sessions);
  }

  /// Bumps a session's position in the list and, the first time it gets a
  /// task, retitles it from that task — mirroring how chat apps title a
  /// conversation from its first message instead of leaving it "New chat".
  Future<void> touchSession(String id, {String? autoTitleFromTask}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readIndex(prefs);
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) return;
    var meta = sessions[index];
    if (autoTitleFromTask != null && meta.title == 'New chat') {
      final trimmed = autoTitleFromTask.trim();
      final title =
          trimmed.length > 48 ? '${trimmed.substring(0, 48)}…' : trimmed;
      meta = meta.copyWith(title: title.isEmpty ? meta.title : title);
    }
    sessions[index] = meta.copyWith(updatedAt: DateTime.now());
    await _writeIndex(prefs, sessions);
  }

  Future<String?> getActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageKeys.activeSessionId);
  }

  Future<void> setActiveSessionId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.activeSessionId, id);
  }

  Future<String?> getRunningSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageKeys.runningSessionId);
  }

  Future<AgentState> loadState(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return loadStateWith(prefs, sessionId);
  }

  AgentState loadStateWith(SharedPreferences prefs, String sessionId) {
    final raw = prefs.getString(StorageKeys.sessionState(sessionId));
    if (raw == null) return AgentState.initial();
    try {
      return AgentState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AgentState.initial();
    }
  }

  Future<void> persistState(
      SharedPreferences prefs, String sessionId, AgentState state) async {
    await prefs.setString(
      StorageKeys.sessionState(sessionId),
      jsonEncode(state.toJson()),
    );
  }

  Future<List<LogEntry>> loadLog(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return loadLogWith(prefs, sessionId);
  }

  List<LogEntry> loadLogWith(SharedPreferences prefs, String sessionId) {
    final raw = prefs.getString(StorageKeys.sessionLog(sessionId));
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> appendLog(
      SharedPreferences prefs, String sessionId, LogEntry entry) async {
    final list = loadLogWith(prefs, sessionId);
    list.add(entry);
    final trimmed = list.length > _maxLogEntriesPerSession
        ? list.sublist(list.length - _maxLogEntriesPerSession)
        : list;
    await prefs.setString(
      StorageKeys.sessionLog(sessionId),
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<ChatSessionMeta>> _readIndex(SharedPreferences prefs) async {
    final raw = prefs.getString(StorageKeys.sessionsIndex);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => ChatSessionMeta.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(
      SharedPreferences prefs, List<ChatSessionMeta> sessions) async {
    await prefs.setString(
      StorageKeys.sessionsIndex,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }
}
