import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'agent_loop_service.dart';
import 'notification_service.dart';

const String backgroundNotificationChannelId = 'claco_agent_channel';

/// Registers and configures the `flutter_background_service` isolate that
/// hosts the ReAct loop (spec 4.1). Must run once from `main()` before the
/// service is started.
Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      autoStartOnBoot: false,
      notificationChannelId: backgroundNotificationChannelId,
      initialNotificationTitle: 'Claco Agent',
      initialNotificationContent: 'Idle',
      foregroundServiceNotificationId: 990011,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();

  final loop = AgentLoopService(service);

  service.on('startTask').listen((event) {
    final task = event?['task'] as String? ?? '';
    if (task.trim().isEmpty) return;
    loop.start(task.trim());
  });

  service.on('stopLoop').listen((event) {
    loop.stop();
  });

  service.on('stopService').listen((event) {
    loop.stop();
    service.stopSelf();
  });
}
