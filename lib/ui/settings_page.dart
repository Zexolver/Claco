import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsService.instance;
  bool _networkDownloadsEnabled = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _settings.networkDownloadsEnabled();
    if (!mounted) return;
    setState(() {
      _networkDownloadsEnabled = enabled;
      _loaded = true;
    });
  }

  Future<void> _setNetworkDownloadsEnabled(bool value) async {
    await _settings.setNetworkDownloadsEnabled(value);
    if (!mounted) return;
    setState(() => _networkDownloadsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Network',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Allow the agent to download resources'),
                  subtitle: const Text(
                    'Lets the agent fetch whatever it decides it needs '
                    'mid-task — docs, code, data files — via its '
                    'download_resource tool, and lets the Model Manager '
                    'fetch GGUF models. Turn this off if you\'re fully '
                    'offline or on a limited data plan; already-downloaded '
                    'files keep working either way.',
                  ),
                  value: _networkDownloadsEnabled,
                  onChanged: _setNetworkDownloadsEnabled,
                ),
              ],
            ),
    );
  }
}
