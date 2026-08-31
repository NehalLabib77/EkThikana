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

  // ---------------------------------------------------------------------------
  // Channel architecture
  // ---------------------------------------------------------------------------
  // Two notification channels are declared on the OS so users can control each
  // independently in Settings → Apps → Gochano → Notifications.
  //
  // Channel IDs are intentionally kept under the legacy `ekthikana_*` prefix
  // (per docs/GOCHANO_BRANDING.md). Renaming these IDs would register new
  // channels and discard the user's per-channel preferences — every existing
  // user's mute/vibration settings would reset.
  //
  //   reminders   → tasks, due dates, "today" nudges
  //   medicine    → daily medicine reminders (with Taken / Skip actions)
  //
  // Both channels are categorised as `reminder` so Android routes them
  // through the correct priority lane (DND-aware, shown above notification
  // shade content) and so accessibility services announce "Reminder" instead
  // of "Notification".
  static const String kChannelRemindersId = 'ekthikana_reminders';
  static const String kChannelRemindersName = 'Gochano Reminders';
  static const String kChannelRemindersDesc = 'Task and daily-life reminders';

  static const String kChannelMedicineId = 'ekthikana_medicine';
  static const String kChannelMedicineName = 'Gochano Medicine Reminders';
  static const String kChannelMedicineDesc =
      'User-confirmed medicine reminder times';

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

  /// Common AndroidNotificationDetails for both channels. Kept as a single
  /// factory so future tweaks (e.g. sound file, vibration pattern) apply
  /// everywhere at once and stay consistent across reminder types.
  static AndroidNotificationDetails _details({
    required String channelId,
    required String channelName,
    required String channelDescription,
    List<AndroidNotificationAction>? actions,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: '@drawable/ic_stat_gochano',
      enableVibration: true,
      playSound: true,
      actions: actions,
    );
  }

  /// Probe whether the OS is currently allowing us to post notifications.
  ///
  /// Returns null on non-Android platforms or when the plugin has not yet
  /// been initialised.  Returns false when the user has denied
  /// POST_NOTIFICATIONS (Android 13+) or disabled notifications for the app
  /// at the OS level (older Android versions).
  static Future<bool?> areNotificationsEnabled() async {
    if (!_ready) return null;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.areNotificationsEnabled();
  }

  /// Open the OS notification-settings screen for this app so the user can
  /// re-grant POST_NOTIFICATIONS or re-enable a muted channel.  Returns true
  /// if the OS accepted the request.
  static Future<bool> openNotificationSettings() async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return (await android?.requestNotificationsPermission()) ?? false;
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

    // First-launch permission prompt.  On Android 12 and below the OS returns
    // granted by default; on Android 13+ (API 33) POST_NOTIFICATIONS becomes
    // a runtime permission and the user actually sees a dialog.  We do NOT
    // show our own pre-prompt here — that responsibility lives in
    // `NotificationPermissionDialog`, which screens can invoke at a context-
    // appropriate moment (e.g. when the user adds their first reminder).
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

  static int _taskNotificationId(String taskId) =>
      taskId.hashCode & 0x7fffffff;

  /// Exposed for tests so we can pin the deterministic id policy without
  /// having to spin up the platform channel. Schedule and cancel MUST use
  /// the same id for a given taskId or notifications leak.
  @visibleForTesting
  static int debugTaskNotificationId(String taskId) =>
      _taskNotificationId(taskId);

  static Future<void> scheduleTask({
    required String taskId,
    required String title,
    required DateTime when,
  }) async {
    await init();
    if (!when.isAfter(DateTime.now())) return;

    await plugin.zonedSchedule(
      id: _taskNotificationId(taskId),
      title: 'Gochano reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: _details(
          channelId: kChannelRemindersId,
          channelName: kChannelRemindersName,
          channelDescription: kChannelRemindersDesc,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: taskId,
    );
  }

  /// Cancel an existing reminder and (if [when] is still in the future) schedule
  /// a new one with the same id. This is the single safe primitive for an edit
  /// flow because it guarantees the notification id is recycled — a manual
  /// cancel+schedule pair would risk id drift if the two helpers ever diverged.
  ///
  /// When [when] is null or not in the future the task is treated as cleared and
  /// only the cancel side runs.
  static Future<void> rescheduleTask({
    required String taskId,
    required String title,
    DateTime? when,
  }) async {
    await init();
    await plugin.cancel(id: _taskNotificationId(taskId));
    if (when == null || !when.isAfter(DateTime.now())) return;
    await plugin.zonedSchedule(
      id: _taskNotificationId(taskId),
      title: 'Gochano reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: _details(
          channelId: kChannelRemindersId,
          channelName: kChannelRemindersName,
          channelDescription: kChannelRemindersDesc,
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
      notificationDetails: NotificationDetails(
        android: _details(
          channelId: kChannelMedicineId,
          channelName: kChannelMedicineName,
          channelDescription: kChannelMedicineDesc,
          actions: const [
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
    await plugin.cancel(id: _taskNotificationId(taskId));
  }
}
