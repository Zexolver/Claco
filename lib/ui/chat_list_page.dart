import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/chat_session.dart';
import '../services/huggingface_service.dart';
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
  final _service = FlutterBackgroundService();
  Timer? _pollTimer;

  List<ChatSessionMeta> _sessionList = [];
  bool _modelLoaded = false;
  String _modelLoadError = '';
  bool _serviceRunning = false;
  bool _loadingModel = false;
  DateTime? _loadStartedAt;
  bool _modelFileExists = false;
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
    final running = await _service.isRunning();
    final loaded = prefs.getBool(StorageKeys.modelLoaded) ?? false;
    final error = prefs.getString(StorageKeys.modelLoadError) ?? '';
    final startedAtMs = prefs.getInt(StorageKeys.modelLoadStartedAt);
    final fileExists = await _checkModelFileExists(prefs);
    if (!mounted) return;
    setState(() {
      _sessionList = list;
      _modelLoaded = loaded;
      _modelLoadError = error;
      _serviceRunning = running;
      _modelFileExists = fileExists;
      if (startedAtMs != null) {
        _loadStartedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
      }
      if (running && !loaded && error.isEmpty) {
        _loadingModel = true;
      } else if (_loadingModel && (loaded || error.isNotEmpty)) {
        _loadingModel = false;
      }
      _runningSessionId = prefs.getString(StorageKeys.runningSessionId);
    });
  }

  Future<bool> _checkModelFileExists(SharedPreferences prefs) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final fileName = prefs.getString(StorageKeys.selectedModelFile) ??
        HuggingFaceService.recommendedFile;
    return File('${docsDir.path}/models/$fileName').existsSync();
  }

  Future<void> _quickLoadModel() async {
    setState(() {
      _loadingModel = true;
      _modelLoadError = '';
      _loadStartedAt = DateTime.now();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.modelLoadAttemptPending);
    if (!_serviceRunning) {
      await _service.startService();
    } else {
      _service.invoke('reloadModel');
    }
  }

  String _loadingElapsedText() {
    final startedAt = _loadStartedAt;
    if (startedAt == null) return 'Loading model…';
    final secs = DateTime.now().difference(startedAt).inSeconds;
    final suffix = secs < 20
        ? ''
        : ' — first load can take a minute or two depending on your device';
    return 'Loading model… ${secs}s$suffix';
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
                _modelLoaded
                    ? Icons.check_circle
                    : _modelLoadError.isNotEmpty
                        ? Icons.error_outline
                        : Icons.circle_outlined,
                size: 16,
                color: _modelLoaded
                    ? Colors.greenAccent
                    : _modelLoadError.isNotEmpty
                        ? Colors.redAccent
                        : Colors.white54,
              ),
              label: Text(
                _modelLoaded
                    ? 'Loaded'
                    : _modelLoadError.isNotEmpty
                        ? 'Load failed'
                        : 'Unloaded',
              ),
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
      body: Column(
        children: [
          if (!_modelLoaded) _buildModelSetupBanner(),
          Expanded(child: _buildChatList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        tooltip: 'New chat',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Guides a first-run (or failed/never-loaded) user straight to a
  /// working model without requiring they notice the small app-bar chip
  /// first — download, load, in-progress, and failure all get their own
  /// clear one-tap state instead of a silent "Unloaded".
  Widget _buildModelSetupBanner() {
    if (_loadingModel) {
      return _setupBannerCard(
        color: Colors.white10,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        text: _loadingElapsedText(),
        button: null,
      );
    }
    if (_modelLoadError.isNotEmpty) {
      return _setupBannerCard(
        color: Colors.red.withValues(alpha: 0.12),
        icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
        text: 'Model failed to load. Tap for details, or retry.',
        button: TextButton(onPressed: _quickLoadModel, child: const Text('Retry')),
        onTap: _openModelManager,
      );
    }
    if (_modelFileExists) {
      return _setupBannerCard(
        color: Colors.white10,
        icon: const Icon(Icons.smart_toy_outlined, color: Colors.white70, size: 20),
        text: 'AI model downloaded but not loaded yet.',
        button: FilledButton(
            onPressed: _quickLoadModel, child: const Text('Load now')),
      );
    }
    return _setupBannerCard(
      color: Colors.white10,
      icon: const Icon(Icons.rocket_launch_outlined, color: Colors.white70, size: 20),
      text: 'Set up the on-device AI model to start using Pagai.',
      button:
          FilledButton(onPressed: _openModelManager, child: const Text('Set up')),
      onTap: _openModelManager,
    );
  }

  Widget _setupBannerCard({
    required Color color,
    required Widget icon,
    required String text,
    required Widget? button,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13)),
            ),
            if (button != null) button,
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return _sessionList.isEmpty
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
