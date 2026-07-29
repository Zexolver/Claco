import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'approval_bridge.dart';

/// Notification ids are fixed per purpose (rather than incrementing) since
/// the loop only ever has one outstanding approval/question at a time; a
/// new approval simply replaces the previous notification.
class NotificationIds {
  NotificationIds._();
  static const approval = 100;
  static const askHuman = 101;
  static const done = 102;
}

class NotificationActionIds {
  NotificationActionIds._();
  static const approve = 'approve';
  static const deny = 'deny';
  static const reply = 'reply';
}

const String _channelId = 'claco_agent_channel';
const String _channelName = 'Claco Agent';
const String _channelDescription =
    'Approval requests and completion pings from the background agent loop.';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// Runs in whatever isolate the notification action was tapped from. Must
/// be a top-level/static function so the Android plugin can invoke it even
/// when the app process (and therefore the UI isolate) is not running.
@pragma('vm:entry-point')
void notificationTapBackgroundHandler(NotificationResponse response) {
  _handleResponse(response);
}

void _handleResponse(NotificationResponse response) {
  final actionId = response.actionId;
  if (actionId == NotificationActionIds.approve) {
    ApprovalBridge.submitDecision('approve');
  } else if (actionId == NotificationActionIds.deny) {
    ApprovalBridge.submitDecision('deny');
  } else if (actionId == NotificationActionIds.reply) {
    final reply = response.input?.trim();
    if (reply != null && reply.isNotEmpty) {
      ApprovalBridge.submitHumanReply(reply);
    }
  }
}

/// Wraps `flutter_local_notifications` for the two human-in-the-loop cases
/// from spec 4.3: a risky-tool approval gate (Approve/Deny buttons) and an
/// `ask_human` clarification request (a text-reply action), plus the plain
/// completion ping for `done`.
class NotificationService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackgroundHandler,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// A "RISKY" action (e.g. `write_file`) is pending; the loop blocks until
  /// the user taps Approve or Deny.
  static Future<void> showApprovalRequest({
    required String toolName,
    required String summary,
  }) async {
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      ongoing: true,
      autoCancel: false,
      actions: [
        AndroidNotificationAction(
          NotificationActionIds.approve,
          'Approve',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationActionIds.deny,
          'Deny',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
    await _plugin.show(
      NotificationIds.approval,
      'Approval needed: $toolName',
      summary,
      const NotificationDetails(android: details),
    );
  }

  /// The agent selected `ask_human`; prompts the user to type a reply
  /// directly from the lock screen notification.
  static Future<void> showAskHuman(String question) async {
    final details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      ongoing: true,
      autoCancel: false,
      actions: [
        AndroidNotificationAction(
          NotificationActionIds.reply,
          'Reply',
          showsUserInterface: false,
          cancelNotification: true,
          inputs: const [AndroidNotificationActionInput(label: 'Your answer')],
        ),
      ],
    );
    await _plugin.show(
      NotificationIds.askHuman,
      'Claco needs input',
      question,
      NotificationDetails(android: details),
    );
  }

  static Future<void> showTaskComplete(String summary) async {
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
    );
    await _plugin.show(
      NotificationIds.done,
      'Task complete',
      summary,
      const NotificationDetails(android: details),
    );
  }

  static Future<void> cancelApprovalPrompts() async {
    await _plugin.cancel(NotificationIds.approval);
    await _plugin.cancel(NotificationIds.askHuman);
  }
}
