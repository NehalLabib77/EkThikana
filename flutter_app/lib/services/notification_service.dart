import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Global reminder types that users can enable/disable independently.
enum ReminderType {
  medicine('medicine', 'Medicine Reminders'),
  task('task', 'Task Reminders'),
  study('study', 'Study Reminders'),
  budget('budget', 'Budget Reminders');

  const ReminderType(this.id, this.label);
  final String id;
  final String label;
}

class NotificationService {
  NotificationService._();

  // ---------------------------------------------------------------------------
  // Channel architecture
  // ---------------------------------------------------------------------------
  // Three notification channels are declared on the OS so users can control each
  // independently in Settings → Apps → Gochano → Notifications.
  //
  // Channel IDs are intentionally kept under the legacy `ekthikana_*` prefix
  // (per docs/GOCHANO_BRANDING.md). Renaming these IDs would register new
  // channels and discard the user's per-channel preferences — every existing
  // user's mute/vibration settings would reset.
  //
  //   reminders   → tasks, due dates, "today" nudges
  //   medicine    → daily medicine reminders (with Taken / Skip actions)
  //   gochano     → global reminders (custom WAV, vibration pattern)
  //
  // All channels are categorised as `reminder` so Android routes them
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

  static const String kChannelGlobalId = 'gochano_reminders_v1';
  static const String kChannelGlobalName = 'Gochano Global Reminders';
  static const String kChannelGlobalDesc =
      'Custom reminders with vibration patterns';

  static final plugin = FlutterLocalNotificationsPlugin();
  static final ValueNotifier<MedicineNotificationAction?> medicineAction =
      ValueNotifier<MedicineNotificationAction?>(null);
  static bool _ready = false;

  /// User's per-type reminder preferences (default: all enabled).
  static final Map<ReminderType, bool> _reminderPrefs = {
    for (final type in ReminderType.values) type: true,
  };

  /// Global vibration toggle (default: enabled).
  static bool _vibrationEnabled = true;

  /// Global sound toggle (default: enabled).
  static bool _soundEnabled = true;

  /// SharedPreferences key prefix for persistent preferences.
  static const String _prefPrefix = 'gochano_notification_';

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
    bool enableVibration = true,
    bool playSound = true,
    String? soundFile,
    Int64List? vibrationPattern,
  }) {
    // Respect the global vibration toggle
    final effectiveVibration = _vibrationEnabled && enableVibration;
    // Respect the global sound toggle
    final effectivePlaySound = _soundEnabled && playSound;

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: '@drawable/ic_stat_gochano',
      enableVibration: effectiveVibration,
      playSound: effectivePlaySound,
      actions: actions,
      sound: (effectivePlaySound && soundFile != null) ? RawResourceAndroidNotificationSound(soundFile) : null,
      vibrationPattern: effectiveVibration ? vibrationPattern : null,
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
  static const _channel = MethodChannel(
    'com.ekthikana.ekthikana/notification_settings',
  );

  static Future<bool> openNotificationSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      return result ?? false;
    } on MissingPluginException {
      // Platform channel not available (e.g. test environment).
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Global reminder user controls
  // ---------------------------------------------------------------------------

  /// Check if a specific reminder type is enabled.
  static bool isReminderEnabled(ReminderType type) {
    return _reminderPrefs[type] ?? true;
  }

  /// Get all reminder preferences.
  static Map<ReminderType, bool> get reminderPreferences =>
      Map.unmodifiable(_reminderPrefs);

  /// Check if vibration is enabled.
  static bool get isVibrationEnabled => _vibrationEnabled;

  /// Toggle a specific reminder type on/off and persist.
  static Future<void> toggleReminder(ReminderType type, {required bool enabled}) async {
    _reminderPrefs[type] = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_prefPrefix}type_${type.id}', enabled);
    } catch (_) {
      // Silently fail if SharedPreferences isn't available
    }
  }

  /// Toggle vibration on/off and persist.
  static Future<void> toggleVibration({required bool enabled}) async {
    _vibrationEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_prefPrefix}vibration', enabled);
    } catch (_) {
      // Silently fail if SharedPreferences isn't available
    }
  }

  /// Check if sound is enabled.
  static bool get isSoundEnabled => _soundEnabled;

  /// Toggle sound on/off and persist.
  static Future<void> toggleSound({required bool enabled}) async {
    _soundEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_prefPrefix}sound', enabled);
    } catch (_) {
      // Silently fail if SharedPreferences isn't available
    }
  }

  /// Load persisted preferences from SharedPreferences.
  static Future<void> _loadPersistedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final type in ReminderType.values) {
        final stored = prefs.getBool('${_prefPrefix}type_${type.id}');
        if (stored != null) {
          _reminderPrefs[type] = stored;
        }
      }
      final vibStored = prefs.getBool('${_prefPrefix}vibration');
      if (vibStored != null) {
        _vibrationEnabled = vibStored;
      }
      final soundStored = prefs.getBool('${_prefPrefix}sound');
      if (soundStored != null) {
        _soundEnabled = soundStored;
      }
    } catch (_) {
      // Silently fail if SharedPreferences isn't available
    }
  }

  /// Custom vibration pattern for global reminders (short pulses).
  static final Int64List _globalVibrationPattern = Int64List.fromList([
    0, 200, 100, 200, 100, 400, // pulse-pulse-long
  ]);

  static Future<void> init() async {
    if (_ready) return;

    await _loadPersistedPreferences();

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

  // ---------------------------------------------------------------------------
  // Task reminders
  // ---------------------------------------------------------------------------

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
    if (!isReminderEnabled(ReminderType.task)) return;

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
    if (!isReminderEnabled(ReminderType.task)) return;

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

  // ---------------------------------------------------------------------------
  // Medicine reminders
  // ---------------------------------------------------------------------------

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
    if (!isReminderEnabled(ReminderType.medicine)) return;

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

  // ---------------------------------------------------------------------------
  // Global reminders (custom WAV, vibration pattern)
  // ---------------------------------------------------------------------------

  static int _globalReminderId(String reminderId) =>
      'global|$reminderId'.hashCode & 0x7fffffff;

  /// Schedule a global reminder with custom sound and vibration.
  ///
  /// [soundFile] is the name of a WAV file in the assets (without extension).
  /// If null, uses the default notification sound.
  ///
  /// [vibrationPattern] overrides the default pattern. If null, uses
  /// [_globalVibrationPattern].
  static Future<void> scheduleGlobalReminder({
    required String reminderId,
    required String title,
    required String body,
    required DateTime when,
    String? soundFile,
    Int64List? vibrationPattern,
    bool repeatDaily = false,
  }) async {
    await init();
    if (!when.isAfter(DateTime.now())) return;

    final effectiveVibration = vibrationPattern ?? _globalVibrationPattern;

    // Cancel any existing schedule before rescheduling to avoid duplicates.
    await plugin.cancel(id: _globalReminderId(reminderId));

    await plugin.zonedSchedule(
      id: _globalReminderId(reminderId),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: _details(
          channelId: kChannelGlobalId,
          channelName: kChannelGlobalName,
          channelDescription: kChannelGlobalDesc,
          enableVibration: true,
          playSound: true,
          soundFile: soundFile,
          vibrationPattern: effectiveVibration,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
      payload: jsonEncode({'kind': 'global', 'reminderId': reminderId}),
    );
  }

  /// Cancel a global reminder.
  static Future<void> cancelGlobalReminder(String reminderId) async {
    await init();
    await plugin.cancel(id: _globalReminderId(reminderId));
  }

  /// Cancel all global reminders.
  static Future<void> cancelAllGlobalReminders() async {
    await init();
    // We can't cancel by prefix, so we track IDs in production.
    // For now, this is a placeholder for the feature.
  }

  // ---------------------------------------------------------------------------
  // Community project task reminders (per-user, deterministic IDs)
  // ---------------------------------------------------------------------------

  /// Deterministic notification id for a community task reminder owned by
  /// a specific user. Uses groupId + projectId + taskId + userId so that
  /// tasks across different groups/projects never collide.
  static int _communityTaskReminderId(
    String groupId,
    String projectId,
    String taskId,
    String userId,
  ) =>
      '$groupId|$projectId|$taskId|$userId'.hashCode & 0x7fffffff;

  static Future<void> scheduleCommunityTaskReminder({
    required String groupId,
    required String projectId,
    required String taskId,
    required String userId,
    required String title,
    required DateTime when,
  }) async {
    await init();
    if (!when.isAfter(DateTime.now())) return;
    if (!isReminderEnabled(ReminderType.task)) return;

    await plugin.zonedSchedule(
      id: _communityTaskReminderId(groupId, projectId, taskId, userId),
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

  static Future<void> rescheduleCommunityTaskReminder({
    required String groupId,
    required String projectId,
    required String taskId,
    required String userId,
    required String title,
    DateTime? when,
  }) async {
    await init();
    await plugin.cancel(
      id: _communityTaskReminderId(groupId, projectId, taskId, userId),
    );
    if (when == null || !when.isAfter(DateTime.now())) return;
    if (!isReminderEnabled(ReminderType.task)) return;

    await plugin.zonedSchedule(
      id: _communityTaskReminderId(groupId, projectId, taskId, userId),
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

  static Future<void> cancelCommunityTaskReminder({
    required String groupId,
    required String projectId,
    required String taskId,
    required String userId,
  }) async {
    await init();
    await plugin.cancel(
      id: _communityTaskReminderId(groupId, projectId, taskId, userId),
    );
  }
}
