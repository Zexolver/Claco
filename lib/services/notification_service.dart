import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';

/// High-priority approval / completion notifications, per spec 4.3.
///
/// Notification action taps are handled by a top-level background
/// callback (a separate isolate on Android), so the only safe way for it
/// to hand a decision back to the paused loop is through durable shared
/// storage — SharedPreferences — which the loop polls.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'pocket_agent_approvals';
  static const String _channelName = 'Agent approvals';
  static const int _approvalNotificationId = 1001;
  static const int _completionNotificationId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('ic_bg_service_small');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    const approvalsChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Approval requests and completion pings from the agent',
      importance: Importance.max,
    );
    // Required by flutter_background_service's foreground notification
    // (AndroidConfiguration.notificationChannelId) — the channel must
    // already exist before the service starts on Android O+.
    const foregroundChannel = AndroidNotificationChannel(
      'pocket_agent_foreground',
      'Pagai running',
      description: 'Persistent notification while the agent loop is active',
      importance: Importance.low,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(approvalsChannel);
    await androidPlugin?.createNotificationChannel(foregroundChannel);
  }

  Future<void> showApprovalRequest({
    required String tool,
    required String params,
  }) async {
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.status,
      fullScreenIntent: true,
      actions: [
        AndroidNotificationAction('approve', 'Approve'),
        AndroidNotificationAction('deny', 'Deny'),
      ],
    );
    await _plugin.show(
      _approvalNotificationId,
      'Agent needs approval: $tool',
      _truncate(params),
      const NotificationDetails(android: details),
    );
  }

  Future<void> showAskHuman(String question) async {
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.max,
      actions: [
        AndroidNotificationAction(
          'reply',
          'Reply',
          inputs: [AndroidNotificationActionInput()],
        ),
      ],
    );
    await _plugin.show(
      _approvalNotificationId,
      'Agent needs input',
      _truncate(question),
      const NotificationDetails(android: details),
    );
  }

  Future<void> showDone(String summary) async {
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      _completionNotificationId,
      'Agent finished the task',
      _truncate(summary),
      const NotificationDetails(android: details),
    );
  }

  Future<void> cancelApprovalRequest() =>
      _plugin.cancel(_approvalNotificationId);

  String _truncate(String s) => s.length > 180 ? '${s.substring(0, 180)}…' : s;
}

@pragma('vm:entry-point')
void _onBackgroundResponse(NotificationResponse response) {
  _handleResponse(response);
}

void _onResponse(NotificationResponse response) {
  _handleResponse(response);
}

Future<void> _handleResponse(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  switch (response.actionId) {
    case 'approve':
      await prefs.setString(StorageKeys.approvalDecision, 'approve');
      break;
    case 'deny':
      await prefs.setString(StorageKeys.approvalDecision, 'deny');
      break;
    case 'reply':
      final text = response.input?.trim() ?? '';
      if (text.isNotEmpty) {
        await prefs.setString(StorageKeys.humanReply, text);
      }
      break;
  }
}
