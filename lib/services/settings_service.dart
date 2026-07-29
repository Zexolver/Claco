import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';

/// App-wide toggles, kept out of SessionService since they aren't
/// per-chat state. Currently just the one Settings switch (spec: "a spot
/// for enabling or disabling allowing download of resources").
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  /// Default true: fresh installs can use the Model Manager immediately.
  /// Users on a limited data plan or who want to stay fully offline can
  /// flip this off in Settings.
  Future<bool> networkDownloadsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.networkDownloadsEnabled) ?? true;
  }

  Future<void> setNetworkDownloadsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.networkDownloadsEnabled, value);
  }
}
