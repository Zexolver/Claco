import 'package:shared_preferences/shared_preferences.dart';

/// Hands off a human decision made from a notification action button back
/// to the background ReAct loop.
///
/// Notification action taps can fire in a separate isolate from the
/// background service loop (especially when the app process was killed), so
/// an in-memory callback cannot bridge them reliably. `SharedPreferences` is
/// backed by native platform storage shared by every Dart isolate in the
/// app, so it works as a simple polling mailbox instead: the loop pauses
/// and polls [consumeDecision]/[consumeHumanReply] on its normal 10s tick
/// (spec 4.1.4) until a response lands.
class ApprovalBridge {
  ApprovalBridge._();

  static const _kDecisionKey = 'claco_approval_decision';
  static const _kHumanReplyKey = 'claco_human_reply';

  static Future<void> submitDecision(String decision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDecisionKey, decision);
  }

  static Future<void> submitHumanReply(String reply) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHumanReplyKey, reply);
  }

  /// Returns and clears a pending approval decision ("approve"/"deny"), or
  /// null if the user has not responded yet.
  static Future<String?> consumeDecision() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kDecisionKey);
    if (value != null) await prefs.remove(_kDecisionKey);
    return value;
  }

  static Future<String?> consumeHumanReply() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kHumanReplyKey);
    if (value != null) await prefs.remove(_kHumanReplyKey);
    return value;
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDecisionKey);
    await prefs.remove(_kHumanReplyKey);
  }
}
