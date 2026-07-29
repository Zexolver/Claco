import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';

/// App-wide toggles, kept out of SessionService since they aren't
/// per-chat state. Currently just the one Settings switch: whether the
/// agent may reach the network at all, for its own download_resource
/// tool calls (Claude-Code-style autonomous fetching) as well as the
/// Model Manager's Hugging Face downloads.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  /// Default true: the agent can fetch what it needs and fresh installs
  /// can use the Model Manager immediately. Users on a limited data plan
  /// or who want to stay fully offline can flip this off in Settings.
  Future<bool> networkDownloadsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.networkDownloadsEnabled) ?? true;
  }

  Future<void> setNetworkDownloadsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.networkDownloadsEnabled, value);
  }
}
