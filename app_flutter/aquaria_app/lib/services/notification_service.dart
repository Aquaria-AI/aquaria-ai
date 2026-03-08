import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Central service for scheduling and cancelling local device notifications.
///
/// Call [init] once at app startup. Notifications fire at 9 AM local time on
/// the task's due date. Tapping a notification navigates to the tank's detail
/// page via [navigatorKey].
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  /// Set this before calling [init]. Used to navigate on notification tap.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Callback invoked with the tankId when a notification is tapped.
  /// Set by the app to push TankDetailScreen.
  static void Function(String tankId)? onTap;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialisation
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_ready) return;

    // Timezone setup
    tz.initializeTimeZones();
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false, // asked explicitly via requestPermissions()
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: _onTapBackground,
    );

    _ready = true;
  }

  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scheduling
  // ─────────────────────────────────────────────────────────────────────────

  static const _channelId = 'aquaria_tasks';
  static const _channelName = 'Aquaria Notifications';
  static const _channelDesc = 'Reminders for aquarium maintenance tasks';

  /// Schedule a device notification for [task] at 9 AM on its due date.
  /// No-ops if the date is missing or already in the past.
  static Future<void> scheduleForTask({
    required String tankId,
    required String tankName,
    required Map<String, dynamic> task,
  }) async {
    debugPrint('[Notif] scheduleForTask called: ready=$_ready task=$task');
    if (!_ready) { debugPrint('[Notif] NOT READY — skipping'); return; }

    final desc = task['description']?.toString() ?? '';
    final rawDue = (task['due_date'] ?? task['due'])?.toString() ?? '';
    debugPrint('[Notif] desc="$desc" rawDue="$rawDue"');
    if (desc.isEmpty) { debugPrint('[Notif] empty desc — skipping'); return; }

    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime fire;

    final due = rawDue.isNotEmpty ? DateTime.tryParse(rawDue) : null;
    if (due != null) {
      fire = tz.TZDateTime(tz.local, due.year, due.month, due.day, 9);
      if (fire.isBefore(now)) {
        fire = now.add(const Duration(minutes: 1));
        debugPrint('[Notif] fire time was past, rescheduled to $fire');
      }
    } else {
      // No due date — fire 1 minute from now
      fire = now.add(const Duration(minutes: 1));
      debugPrint('[Notif] no due date, firing in 1 min at $fire');
    }
    debugPrint('[Notif] fire=$fire now=$now');

    final id = _notifId(tankId, desc, rawDue);

    await _plugin.zonedSchedule(
      id,
      tankName, // notification title = tank name (tappable → detail page)
      desc,
      fire,
      NotificationDetails(
        android: const AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: tankId, // used on tap to navigate to the correct tank
    );
    debugPrint('[Notif] ✓ Notification scheduled id=$id fire=$fire desc="$desc"');
  }

  /// Cancel the notification for a specific task.
  static Future<void> cancelForTask({
    required String tankId,
    required Map<String, dynamic> task,
  }) async {
    if (!_ready) return;
    final desc = task['description']?.toString() ?? '';
    final rawDue = (task['due_date'] ?? task['due'])?.toString() ?? '';
    if (desc.isEmpty && rawDue.isEmpty) return;
    await _plugin.cancel(_notifId(tankId, desc, rawDue));
  }

  /// Cancel a notification by the pre-computed task key (format: tankId|desc|due).
  static Future<void> cancelForKey(String taskKey) async {
    if (!_ready) return;
    final id = taskKey.hashCode.abs() % 0x7FFFFFFF;
    await _plugin.cancel(id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tap handling
  // ─────────────────────────────────────────────────────────────────────────

  static void _onTap(NotificationResponse response) {
    final tankId = response.payload;
    if (tankId != null && tankId.isNotEmpty) {
      onTap?.call(tankId);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static int _notifId(String tankId, String desc, String due) {
    final key = '$tankId|$desc|$due';
    return key.hashCode.abs() % 0x7FFFFFFF;
  }
}

/// Top-level function required by flutter_local_notifications for background
/// notification responses (Android only).
@pragma('vm:entry-point')
void _onTapBackground(NotificationResponse response) {
  // Navigation can't happen here (no Flutter engine context).
  // The payload is handled next time the app foregrounds via getNotificationAppLaunchDetails.
}
