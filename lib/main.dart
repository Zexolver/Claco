import 'package:flutter/material.dart';

import 'app.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notifications must be initialized (and the channel created) before the
  // background service is configured, since the service reuses this
  // channel for both its foreground-service notification and the
  // approval/ask_human/done pings (spec 4.3).
  await NotificationService.init();
  await configureBackgroundService();

  runApp(const ClacoApp());
}
