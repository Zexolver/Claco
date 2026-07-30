import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/hf_model.dart';
import '../services/huggingface_service.dart';
import '../services/settings_service.dart';
import 'settings_page.dart';

/// Lets the user pick which GGUF model the agent runs. Defaults to the
/// exact model CLAUDE.md recommends; everything else is opt-in via a
/// Hugging Face search. Only `.gguf` files are ever listed or downloadable
/// — that's the one format `flutter_llama` can load.
class ModelManagerPage extends StatefulWidget {
  const ModelManagerPage({super.key});

  @override
  State<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends State<ModelManagerPage> {
  final _hf = HuggingFaceService.instance;
  final _service = FlutterBackgroundService();
  final _searchController = TextEditingController();
  Timer? _pollTimer;

  String? _selectedFileName;
  Directory? _modelsDir;
  bool _networkEnabled = true;

  bool _modelLoaded = false;
  String _modelLoadError = '';
  bool _serviceRunning = false;
  bool _loadingModel = false;
  DateTime? _loadStartedAt;

  bool _searching = false;
  String? _searchError;
  List<HfModelSummary> _results = [];

  String? _expandedRepoId;
  bool _loadingFiles = false;
  List<HfGgufFile>? _expandedFiles;
  String? _filesError;

  /// Keyed by "repoId/path" while a download of that file is in flight.
  String? _downloadingKey;
  int _received = 0;
  int _total = 0;
  bool _cancelRequested = false;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _loadState();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _refreshModelStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final docsDir = await getApplicationDocumentsDirectory();
    final networkEnabled =
        await SettingsService.instance.networkDownloadsEnabled();
    if (!mounted) return;
    setState(() {
      _selectedFileName = prefs.getString(StorageKeys.selectedModelFile) ??
          HuggingFaceService.recommendedFile;
      _modelsDir = Directory('${docsDir.path}/models');
      _networkEnabled = networkEnabled;
    });
    await _refreshModelStatus();
  }

  Future<void> _refreshModelStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final running = await _service.isRunning();
    final loaded = prefs.getBool(StorageKeys.modelLoaded) ?? false;
    final error = prefs.getString(StorageKeys.modelLoadError) ?? '';
    final startedAtMs = prefs.getInt(StorageKeys.modelLoadStartedAt);
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _modelLoaded = loaded;
      _modelLoadError = error;
      if (startedAtMs != null) {
        _loadStartedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
      }
      // An attempt is in flight whenever the service is up but hasn't yet
      // resolved to either loaded or errored — catches a reload triggered
      // elsewhere, or one already running when this page opens, not just
      // a tap on this page's own button.
      if (running && !loaded && error.isEmpty) {
        _loadingModel = true;
      } else if (_loadingModel && (loaded || error.isNotEmpty)) {
        _loadingModel = false;
      }
    });
  }

  Future<void> _loadModel() async {
    setState(() {
      _loadingModel = true;
      _modelLoadError = '';
      _loadStartedAt = DateTime.now();
    });
    // An explicit tap always gets one fresh attempt, even if the last one
    // crashed the process and left the "attempt in progress" guard set.
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
    if (startedAt == null) return 'Loading…';
    final elapsed = DateTime.now().difference(startedAt);
    final secs = elapsed.inSeconds;
    final suffix = secs < 20
        ? ''
        : ' — this can take up to a minute or two on the first load, or '
            'on a slower device';
    return 'Loading… ${secs}s$suffix';
  }

  bool _isDownloaded(String fileName) {
    final dir = _modelsDir;
    if (dir == null) return false;
    return File('${dir.path}/$fileName').existsSync();
  }

  Future<void> _selectModel(
      {required String repoId, required String fileName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.selectedModelRepo, repoId);
    await prefs.setString(StorageKeys.selectedModelFile, fileName);
    if (!mounted) return;
    setState(() => _selectedFileName = fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loading $fileName…')),
    );
    // Picking a model should just start using it — no separate "now go
    // press Load" step for the user to have to find and remember.
    await _loadModel();
  }

  Future<void> _download(
      {required String repoId, required HfGgufFile file}) async {
    if (!_networkEnabled) return;
    final dir = _modelsDir;
    if (dir == null) return;
    final fileName = p.basename(file.path);
    final key = '$repoId/${file.path}';
    final destPath = '${dir.path}/$fileName';

    setState(() {
      _downloadingKey = key;
      _received = 0;
      _total = file.sizeBytes;
      _cancelRequested = false;
      _downloadError = null;
    });

    try {
      await _hf.downloadFile(
        repoId: repoId,
        filePath: file.path,
        destPath: destPath,
        isCancelled: () => _cancelRequested,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _downloadingKey = null);
      await _selectModel(repoId: repoId, fileName: fileName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingKey = null;
        _downloadError = _cancelRequested ? null : 'Download failed: $e';
      });
    }
  }

  Future<void> _search() async {
    if (!_networkEnabled) return;
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _expandedRepoId = null;
    });
    try {
      final results = await _hf.searchModels(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchError = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _expandRepo(String repoId) async {
    if (!_networkEnabled) return;
    if (_expandedRepoId == repoId) {
      setState(() => _expandedRepoId = null);
      return;
    }
    setState(() {
      _expandedRepoId = repoId;
      _loadingFiles = true;
      _expandedFiles = null;
      _filesError = null;
    });
    try {
      final files = await _hf.listGgufFiles(repoId);
      if (!mounted) return;
      setState(() => _expandedFiles = files);
    } catch (e) {
      if (!mounted) return;
      setState(() => _filesError = 'Could not list files: $e');
    } finally {
      if (mounted) setState(() => _loadingFiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model Manager')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 12),
          if (!_networkEnabled) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Downloads are disabled in Settings. Already-downloaded '
                      'models can still be used.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      );
                      _loadState();
                    },
                    child: const Text('Settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text('Recommended', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          _buildRecommendedCard(),
          const Divider(height: 32),
          Text('Or search Hugging Face for another model',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  enabled: _networkEnabled,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: 'e.g. "llama 3.2 1b" or a repo like org/name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_searching || !_networkEnabled) ? null : _search,
                child: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Search'),
              ),
            ],
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 8),
            Text(_searchError!,
                style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 8),
          ..._results.map(_buildRepoTile),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _modelLoaded ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: _modelLoaded ? Colors.greenAccent : Colors.white54,
                ),
                const SizedBox(width: 8),
                Text(
                  _modelLoaded ? 'Model loaded' : 'Model not loaded',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (!_loadingModel)
                  FilledButton(
                    onPressed: _loadModel,
                    child: Text(_modelLoaded ? 'Reload' : 'Load model'),
                  ),
              ],
            ),
            if (_loadingModel) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                _loadingElapsedText(),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            if (_modelLoadError.isNotEmpty && !_loadingModel) ...[
              const SizedBox(height: 8),
              Text(
                _modelLoadError,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendedCard() {
    const fileName = HuggingFaceService.recommendedFile;
    final downloaded = _isDownloaded(fileName);
    final isSelected = _selectedFileName == fileName;
    const key = '${HuggingFaceService.recommendedRepoId}/$fileName';
    final isDownloadingThis = _downloadingKey == key;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    HuggingFaceService.recommendedLabel,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (isSelected) const Chip(label: Text('In use')),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              HuggingFaceService.recommendedRepoId,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (isDownloadingThis)
              _buildProgress()
            else
              Row(
                children: [
                  if (downloaded && !isSelected)
                    OutlinedButton(
                      onPressed: () => _selectModel(
                        repoId: HuggingFaceService.recommendedRepoId,
                        fileName: fileName,
                      ),
                      child: const Text('Use this model'),
                    )
                  else if (!downloaded && _networkEnabled)
                    FilledButton.icon(
                      onPressed: () => _download(
                        repoId: HuggingFaceService.recommendedRepoId,
                        file: const HfGgufFile(path: fileName, sizeBytes: 0),
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    )
                  else if (!downloaded && !_networkEnabled)
                    const Text(
                      'Downloads disabled in Settings',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepoTile(HfModelSummary model) {
    final expanded = _expandedRepoId == model.repoId;
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(model.repoId),
            subtitle:
                Text('${model.downloads} downloads · ${model.likes} likes'),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => _expandRepo(model.repoId),
          ),
          if (expanded) _buildFileList(model.repoId),
        ],
      ),
    );
  }

  Widget _buildFileList(String repoId) {
    if (_loadingFiles) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_filesError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child:
            Text(_filesError!, style: const TextStyle(color: Colors.redAccent)),
      );
    }
    final files = _expandedFiles ?? [];
    if (files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No .gguf files found in this repo.'),
      );
    }
    return Column(
      children: files.map((f) => _buildFileTile(repoId, f)).toList(),
    );
  }

  Widget _buildFileTile(String repoId, HfGgufFile file) {
    final fileName = p.basename(file.path);
    final downloaded = _isDownloaded(fileName);
    final isSelected = _selectedFileName == fileName;
    final key = '$repoId/${file.path}';
    final isDownloadingThis = _downloadingKey == key;

    return ListTile(
      dense: true,
      title: Text(file.path),
      subtitle: isDownloadingThis
          ? _buildProgress()
          : Text(file.readableSize,
              style: const TextStyle(color: Colors.white54)),
      trailing: isDownloadingThis
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () => setState(() => _cancelRequested = true),
            )
          : isSelected
              ? const Chip(label: Text('In use'))
              : downloaded
                  ? OutlinedButton(
                      onPressed: () =>
                          _selectModel(repoId: repoId, fileName: fileName),
                      child: const Text('Use'),
                    )
                  : IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Download',
                      onPressed: () => _download(repoId: repoId, file: file),
                    ),
    );
  }

  Widget _buildProgress() {
    final progress = _total > 0 ? _received / _total : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 4),
        Text(
          _total > 0
              ? '${(_received / (1024 * 1024)).toStringAsFixed(1)} / '
                  '${(_total / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(_received / (1024 * 1024)).toStringAsFixed(1)} MB',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        if (_downloadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_downloadError!,
                style: const TextStyle(color: Colors.redAccent)),
          ),
      ],
    );
  }
}
