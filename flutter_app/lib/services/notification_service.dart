import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_config.dart';

class MedicineNotificationAction {
  const MedicineNotificationAction({
    required this.action,
    required this.medicineId,
    required this.medicineName,
    required this.hhmm,
    required this.quantityPerDose,
    required this.unitPrice,
    required this.unit,
  });

  final String action;
  final String medicineId;
  final String medicineName;
  final String hhmm;
  final double quantityPerDose;
  final double unitPrice;
  final String unit;
}

class NotificationService {
  NotificationService._();

  static final plugin = FlutterLocalNotificationsPlugin();
  static final ValueNotifier<MedicineNotificationAction?> medicineAction =
      ValueNotifier<MedicineNotificationAction?>(null);
  static bool _ready = false;

  @pragma('vm:entry-point')
  static void _backgroundResponse(NotificationResponse response) {
    // Background isolates must not write Firebase data directly. The action
    // opens the app (showsUserInterface=true); the foreground callback then
    // performs the user-confirmed operation.
  }

  static Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConfig.bangladeshTimeZone));

    // Use the monochrome notification small icon (white-on-transparent vector).
    // The launcher icon (Gochano.png) must never be used as a status-bar icon -
    // Android would render it as a solid white square.
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_gochano'),
    );

    await plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundResponse,
    );

    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _onResponse(launch!.notificationResponse!);
    }

    _ready = true;
  }

  static void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || !payload.startsWith('{')) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['kind'] != 'medicine') return;
      final actionId = response.actionId?.trim();
      if (actionId == null || actionId.isEmpty) return;
      medicineAction.value = MedicineNotificationAction(
        action: actionId,
        medicineId: data['medicineId']?.toString() ?? '',
        medicineName: data['medicineName']?.toString() ?? '',
        hhmm: data['hhmm']?.toString() ?? '',
        quantityPerDose: (data['quantityPerDose'] as num?)?.toDouble() ?? 1,
        unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
        unit: data['unit']?.toString() ?? 'tablet',
      );
    } catch (_) {
      // Ignore malformed legacy payloads.
    }
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
      title: 'Gochano reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'ekthikana_reminders',
          'Gochano Reminders',
          channelDescription: 'Task and daily-life reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_gochano',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: taskId,
    );
  }

  static int _medicineNotificationId(String medicineId, String hhmm) =>
      '$medicineId|$hhmm'.hashCode & 0x7fffffff;

  /// Exposed for tests so we can pin the deterministic id policy without
  /// having to spin up the platform channel.
  @visibleForTesting
  static int debugMedicineNotificationId(String medicineId, String hhmm) =>
      _medicineNotificationId(medicineId, hhmm);

  static Future<void> scheduleDailyMedicine({
    required String medicineId,
    required String medicineName,
    required String hhmm,
    String instruction = '',
    double quantityPerDose = 1,
    double unitPrice = 0,
    String unit = 'tablet',
  }) async {
    await init();
    final parts = hhmm.split(':');
    if (parts.length != 2) return;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return;

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    final payload = jsonEncode({
      'kind': 'medicine',
      'medicineId': medicineId,
      'medicineName': medicineName,
      'hhmm': hhmm,
      'quantityPerDose': quantityPerDose,
      'unitPrice': unitPrice,
      'unit': unit,
    });

    await plugin.zonedSchedule(
      id: _medicineNotificationId(medicineId, hhmm),
      title: 'Gochano • Medicine reminder',
      body: instruction.trim().isEmpty
          ? '$medicineName • $quantityPerDose $unit'
          : '$medicineName • $instruction',
      scheduledDate: next,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'ekthikana_medicine',
          'Gochano Medicine Reminders',
          channelDescription: 'User-confirmed medicine reminder times',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_gochano',
          actions: [
            AndroidNotificationAction(
              'taken',
              'Taken',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'skip',
              'Skip',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  static Future<void> cancelMedicineTimes(
    String medicineId,
    Iterable<String> times,
  ) async {
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
