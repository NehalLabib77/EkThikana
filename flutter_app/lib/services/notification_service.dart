import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_config.dart';
import '../core/localization/gochano_language.dart';

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
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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

    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    // Request POST_NOTIFICATIONS permission (Android 13+). On older Android
    // the OS grants this by default, so the call is a no-op.
    await android?.requestNotificationsPermission();

    // Request exact-alarm access (Android 12+). The SCHEDULE_EXACT_ALARM
    // manifest declaration alone is NOT sufficient — the user must grant
    // the permission through the system dialog. Without this call,
    // canScheduleExactNotifications() returns false and all task reminders
    // fall back to inexactAllowWhileIdle, which Android Doze mode may
    // delay or suppress when the app is backgrounded.
    try {
      final canExact = await android?.canScheduleExactNotifications() ?? false;
      if (!canExact) {
        await android?.requestExactAlarmsPermission();
      }
    } catch (_) {
      // Some OEMs throw — safe to ignore; inexact fallback handles it.
    }

    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _onResponse(launch!.notificationResponse!);
    }

    _ready = true;

    // DEBUG: audit pending alarms surviving from previous sessions.
    if (kDebugMode) {
      try {
        final pending = await plugin.pendingNotificationRequests();
        final taskPending = pending.where((r) => '${r.id}'.isNotEmpty).toList();
        debugPrint(
          '[TaskReminderRestoreAudit]'
          ' totalPending=${pending.length}'
          ' sampleIds=${taskPending.take(5).map((r) => r.id).toList()}',
        );
        final notificationsOn =
            await android?.areNotificationsEnabled() ?? false;
        final exactOn = await android?.canScheduleExactNotifications() ?? false;
        debugPrint(
          '[TaskReminderRestoreAudit]'
          ' notificationsAllowed=$notificationsOn'
          ' exactCapability=$exactOn',
        );
      } catch (e) {
        debugPrint('[TaskReminderRestoreAudit] audit failed: $e');
      }
    }
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

  static const List<int> _taskReminderOffsets = [90, 60, 30, 10, 0, -30];

  static int _taskNotificationId(String taskId, [int offsetMinutes = 0]) =>
      _stableStringId('task_${taskId}_$offsetMinutes');

  /// Exposed for tests so we can pin the deterministic id policy without
  /// having to spin up the platform channel. Schedule and cancel MUST use
  /// the same id for a given taskId or notifications leak.
  @visibleForTesting
  static int debugTaskNotificationId(String taskId, [int offsetMinutes = 0]) =>
      _taskNotificationId(taskId, offsetMinutes);

  static Future<void> scheduleTask({
    required String taskId,
    required String title,
    required DateTime when,
    String type = 'task',
  }) async {
    await init();
    if (!when.isAfter(DateTime.now())) return;
    final now = DateTime.now();
    // Items >= 30m past due are already missed; do not schedule past reminders.
    final missedAt = when.add(const Duration(minutes: 30));
    if (!missedAt.isAfter(now)) return;

    final scheduleMode = await _resolveScheduleMode();
    final isAssignment = type == 'assignment';
    final scheduledIds = <int>[];

    for (final offset in _taskReminderOffsets) {
      final notifyAt = when.subtract(Duration(minutes: offset));
      if (!notifyAt.isAfter(now)) continue;

      final notifId = _taskNotificationId(taskId, offset);
      final slotLabel = offset > 0
          ? 'T-$offset'
          : offset == 0
          ? 'T'
          : 'T+${-offset}';

      await plugin.zonedSchedule(
        id: notifId,
        title: 'Gochano reminder',
        body: isAssignment
            ? (offset == -30
                  ? GochanoLanguage.text(
                      'Assignment incomplete',
                      'অ্যাসাইনমেন্টটি এখনো সম্পন্ন হয়নি',
                    )
                  : offset == 0
                  ? GochanoLanguage.text(
                      'Assignment due now: $title',
                      'অ্যাসাইনমেন্টের সময় হয়েছে: $title',
                    )
                  : '$title (in $offset mins)')
            : (offset == -30
                  ? GochanoLanguage.text(
                      'Task incomplete',
                      'কাজটি এখনো সম্পন্ন হয়নি',
                    )
                  : offset == 0
                  ? GochanoLanguage.text(
                      'Task due now: $title',
                      'কাজের সময় হয়েছে: $title',
                    )
                  : '$title (in $offset mins)'),
        scheduledDate: tz.TZDateTime.from(notifyAt, tz.local),
        notificationDetails: NotificationDetails(
          android: _details(
            channelId: kChannelRemindersId,
            channelName: kChannelRemindersName,
            channelDescription: kChannelRemindersDesc,
          ),
        ),
        androidScheduleMode: scheduleMode,
        payload: taskId,
      );

      scheduledIds.add(notifId);
      if (kDebugMode) {
        debugPrint(
          '[TaskReminderSchedule] taskId=$taskId'
          ' slot=$slotLabel'
          ' scheduledLocal=$notifyAt'
          ' notificationId=$notifId'
          ' timezone=Asia/Dhaka'
          ' mode=$scheduleMode',
        );
      }
    }

    if (kDebugMode && scheduledIds.isNotEmpty) {
      try {
        final pending = await plugin.pendingNotificationRequests();
        final pendingIds = pending.map((r) => r.id).toSet();
        final expectedIds = scheduledIds.toSet();
        final missing = expectedIds.difference(pendingIds);
        debugPrint(
          '[TaskReminderPending] taskId=$taskId'
          ' expected=$expectedIds'
          ' present=${pendingIds.intersection(expectedIds)}'
          ' missing=$missing',
        );
      } catch (e) {
        debugPrint('[TaskReminderPending] pending query failed: $e');
      }
    }
  }

  /// Cancel an existing reminder and (if [when] is still in the future) schedule
  /// a new one across all offsets [90, 60, 30, 0].
  /// Cancel an existing reminder and (if [when] + 30m is still in the future) schedule
  /// a new one across all offsets [90, 60, 30, 10, 0, -30].
  ///
  /// When [when] is null or not in the future the task is treated as cleared and
  /// only the cancel side runs.
  /// When [when] is null or [when] + 30m is not in the future, the task is treated as
  /// cleared/missed and only the cancel side runs.
  static Future<void> rescheduleTask({
    required String taskId,
    required String title,
    DateTime? when,
    String type = 'task',
  }) async {
    await init();
    if (kDebugMode) {
      debugPrint('[TaskReminderSchedule] reschedule taskId=$taskId when=$when');
    }
    for (final offset in _taskReminderOffsets) {
      await plugin.cancel(id: _taskNotificationId(taskId, offset));
    }
    if (when == null) return;
    final missedAt = when.add(const Duration(minutes: 30));
    if (!missedAt.isAfter(DateTime.now())) return;
    await scheduleTask(taskId: taskId, title: title, when: when, type: type);
  }

  static const List<int> _medicineFollowUpOffsets = [0, 30, 60, 90, 120];
  static Future<void> cancelTask(String taskId) async {
    await init();
    if (kDebugMode) {
      debugPrint('[TaskReminderSchedule] cancelTask taskId=$taskId');
    }
    for (final offset in _taskReminderOffsets) {
      await plugin.cancel(id: _taskNotificationId(taskId, offset));
    }
  }

  static int _medicineNotificationId(
    String medicineId,
    String hhmm, [
    int offsetMinutes = 0,
  ]) => _stableStringId('medicine_${medicineId}_${hhmm}_$offsetMinutes');

  /// Exposed for tests so we can pin the deterministic id policy without
  /// having to spin up the platform channel.
  @visibleForTesting
  static int debugMedicineNotificationId(
    String medicineId,
    String hhmm, [
    int offsetMinutes = 0,
  ]) => _medicineNotificationId(medicineId, hhmm, offsetMinutes);

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

    final scheduleMode = await _resolveScheduleMode();

    // Base dose at scheduled time (offset 0), repeats daily
    await plugin.zonedSchedule(
      id: _medicineNotificationId(medicineId, hhmm, 0),
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
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );

    // Follow-ups at 30, 60, 90, 120 minutes
    for (final offset in _medicineFollowUpOffsets.skip(1)) {
      final followUpTime = next.add(Duration(minutes: offset));
      await plugin.zonedSchedule(
        id: _medicineNotificationId(medicineId, hhmm, offset),
        title: 'Gochano • Medicine reminder (follow-up)',
        body: '$medicineName • Overdue ($offset min) — please take or skip',
        scheduledDate: followUpTime,
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
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
    }
  }

  /// Cancels follow-ups for a dose that was resolved today (Taken/Skipped),
  /// while keeping the repeating base schedule intact for future days.
  static Future<void> cancelSameDayMedicineDose(
    String medicineId,
    String hhmm,
  ) async {
    await init();
    // Only cancel follow-ups (30, 60, 90, 120) for today.
    // Offset 0 is scheduled with matchDateTimeComponents: DateTimeComponents.time
    // to repeat daily; cancelling offset 0 would cancel future days' daily alarms.
    for (final offset in _medicineFollowUpOffsets.where((o) => o > 0)) {
      await plugin.cancel(
        id: _medicineNotificationId(medicineId, hhmm, offset),
      );
    }
  }

  static Future<void> cancelMedicineTimes(
    String medicineId,
    Iterable<String> times,
  ) async {
    await init();
    for (final time in times) {
      for (final offset in _medicineFollowUpOffsets) {
        await plugin.cancel(
          id: _medicineNotificationId(medicineId, time, offset),
        );
      }
    }
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
  ) => '$groupId|$projectId|$taskId|$userId'.hashCode & 0x7fffffff;

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

  /// Resolves the safe scheduling mode on Android.
  /// Uses exactAllowWhileIdle when exact-alarm capability is granted/supported,
  /// otherwise falls back to inexactAllowWhileIdle without requesting dangerous
  /// permissions or crashing.
  static Future<AndroidScheduleMode> _resolveScheduleMode() async {
    try {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canExact = await android?.canScheduleExactNotifications() ?? false;
      final notificationsAllowed =
          await android?.areNotificationsEnabled() ?? false;
      if (kDebugMode) {
        debugPrint(
          '[TaskReminderSchedule] notificationsAllowed=$notificationsAllowed'
          ' exactCapability=$canExact'
          ' mode=${canExact ? "exactAllowWhileIdle" : "inexactAllowWhileIdle"}',
        );
      }
      return canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TaskReminderSchedule] exactCapability check failed: $e');
      }
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  /// FNV-1a 32-bit hash over the code-units of [input].
  ///
  /// Unlike Dart's `String.hashCode`, this is a fixed algorithm whose output
  /// depends only on the character content of the string. It is stable across
  /// process restarts, device reboots, and Dart VM sessions.
  ///
  /// The result is masked to 31 bits (`& 0x7fffffff`) so that it is always a
  /// non-negative integer suitable for Android notification IDs.
  static int _stableStringId(String input) {
    // FNV-1a parameters (32-bit).
    const int fnvOffsetBasis = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffsetBasis;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * fnvPrime) & 0xffffffff; // keep 32-bit
    }
    return hash & 0x7fffffff; // positive 31-bit
  }

  static int _commuteTripReminderId(String tripId) {
    return _stableStringId('commute_trip_$tripId');
  }

  static Future<void> scheduleCommuteTripReminder({
    required String tripId,
    required String title,
    required DateTime when,
  }) async {
    await init();
    if (!when.isAfter(DateTime.now())) return;
    final scheduleMode = await _resolveScheduleMode();
    await plugin.zonedSchedule(
      id: _commuteTripReminderId(tripId),
      title: 'Commute reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: _details(
          channelId: kChannelRemindersId,
          channelName: kChannelRemindersName,
          channelDescription: kChannelRemindersDesc,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: 'commute_trip:$tripId',
    );
  }

  static Future<void> rescheduleCommuteTripReminder({
    required String tripId,
    required String title,
    DateTime? when,
  }) async {
    await init();
    await plugin.cancel(id: _commuteTripReminderId(tripId));
    if (when == null || !when.isAfter(DateTime.now())) return;
    final scheduleMode = await _resolveScheduleMode();
    await plugin.zonedSchedule(
      id: _commuteTripReminderId(tripId),
      title: 'Commute reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: _details(
          channelId: kChannelRemindersId,
          channelName: kChannelRemindersName,
          channelDescription: kChannelRemindersDesc,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: 'commute_trip:$tripId',
    );
  }

  static Future<void> cancelCommuteTripReminder(String tripId) async {
    await init();
    await plugin.cancel(id: _commuteTripReminderId(tripId));
  }

  @visibleForTesting
  static int debugCommuteTripNotificationId(String tripId) {
    return _commuteTripReminderId(tripId);
  }
}
