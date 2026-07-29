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
                  title: const Text('Allow downloading resources'),
                  subtitle: const Text(
                    'Lets the app fetch resources over the network — '
                    'currently just GGUF models in the Model Manager. '
                    'Turn this off if you\'re fully offline or on a '
                    'limited data plan; the ReAct loop itself never '
                    'needs the network either way.',
                  ),
                  value: _networkDownloadsEnabled,
                  onChanged: _setNetworkDownloadsEnabled,
                ),
              ],
            ),
    );
  }
}
