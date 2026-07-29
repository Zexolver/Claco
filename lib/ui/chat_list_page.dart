import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/chat_session.dart';
import '../services/session_service.dart';
import 'chat_page.dart';
import 'model_manager_page.dart';
import 'settings_page.dart';

/// The app's home screen — a list of chats (Claude-mobile-app style)
/// rather than one single running conversation. Tapping a chat opens its
/// ChatPage; only one chat's agent loop can run at a time, but every
/// chat keeps its own independent transcript and task.
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _sessions = SessionService.instance;
  Timer? _pollTimer;

  List<ChatSessionMeta> _sessionList = [];
  bool _modelLoaded = false;
  String? _runningSessionId;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await _sessions.listSessions();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sessionList = list;
      _modelLoaded = prefs.getBool(StorageKeys.modelLoaded) ?? false;
      _runningSessionId = prefs.getString(StorageKeys.runningSessionId);
    });
  }

  Future<void> _newChat() async {
    final meta = await _sessions.createSession();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(sessionId: meta.id, initialTitle: meta.title),
      ),
    );
    _refresh();
  }

  Future<void> _openChat(ChatSessionMeta meta) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(sessionId: meta.id, initialTitle: meta.title),
      ),
    );
    _refresh();
  }

  Future<void> _deleteChat(ChatSessionMeta meta) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text('This deletes "${meta.title}" and its whole transcript.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sessions.deleteSession(meta.id);
    _refresh();
  }

  Future<void> _openModelManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ModelManagerPage()),
    );
    _refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagai'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: Icon(
                _modelLoaded ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: _modelLoaded ? Colors.greenAccent : Colors.white54,
              ),
              label: Text(_modelLoaded ? 'Loaded' : 'Unloaded'),
              visualDensity: VisualDensity.compact,
              onPressed: _openModelManager,
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _sessionList.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No chats yet.\nTap + to start one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : ListView.builder(
              itemCount: _sessionList.length,
              itemBuilder: (context, index) {
                final meta = _sessionList[index];
                final isRunning = _runningSessionId == meta.id;
                return Dismissible(
                  key: ValueKey(meta.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.redAccent,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    await _deleteChat(meta);
                    return false; // _deleteChat already refreshes the list
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isRunning
                          ? Colors.greenAccent.withValues(alpha: 0.2)
                          : null,
                      child: Icon(
                        isRunning ? Icons.bolt : Icons.chat_bubble_outline,
                        color: isRunning ? Colors.greenAccent : null,
                      ),
                    ),
                    title: Text(meta.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_relativeTime(meta.updatedAt)),
                    trailing: isRunning
                        ? const Chip(
                            label: Text('Running'),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                    onTap: () => _openChat(meta),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        tooltip: 'New chat',
        child: const Icon(Icons.add),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
