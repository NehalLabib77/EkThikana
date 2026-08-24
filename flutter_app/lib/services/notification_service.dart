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
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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

  static int _medicineNotificationId(String medicineId, String hhmm) =>
      '$medicineId|$hhmm'.hashCode & 0x7fffffff;

  static Future<void> scheduleDailyMedicine({
    required String medicineId,
    required String medicineName,
    required String hhmm,
    String instruction = '',
  }) async {
    await init();
    final parts = hhmm.split(':');
    if (parts.length != 2) return;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return;

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    await plugin.zonedSchedule(
      id: _medicineNotificationId(medicineId, hhmm),
      title: 'Medicine reminder',
      body: instruction.trim().isEmpty ? medicineName : '$medicineName • $instruction',
      scheduledDate: next,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'ekthikana_medicine',
          'Medicine reminders',
          channelDescription: 'Confirmed medicine reminder times',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'medicine:$medicineId',
    );
  }

  static Future<void> cancelMedicineTimes(String medicineId, Iterable<String> times) async {
    await init();
    for (final time in times) {
      await plugin.cancel(id: _medicineNotificationId(medicineId, time));
    }
  }

  static Future<void> cancelTask(String taskId) async {
    await init();
    await plugin.cancel(id: taskId.hashCode & 0x7fffffff);
  }
}
