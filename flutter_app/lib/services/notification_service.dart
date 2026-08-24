import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_config.dart';

class NotificationService {
  NotificationService._();

  static final plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConfig.bangladeshTimeZone));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('app_icon'),
    );

    await plugin.initialize(settings: settings);

    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  static Future<void> scheduleTask({
    required String taskId,
    required String title,
    required DateTime when,
  }) async {
    await init();
    if (!when.isAfter(DateTime.now())) return;

    final id = taskId.hashCode & 0x7fffffff;
    await plugin.zonedSchedule(
      id: id,
      title: 'EkThikana reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'ekthikana_reminders',
          'Reminders',
          channelDescription: 'Task and daily-life reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: taskId,
    );
  }

  static Future<void> cancelTask(String taskId) async {
    await init();
    await plugin.cancel(id: taskId.hashCode & 0x7fffffff);
  }
}
