import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_config.dart';
import '../core/localization/gochano_language.dart';
import '../models/local_reminder.dart';
import 'firestore_service.dart';
import 'local_reminder_store.dart';

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

class TaskNotificationAction {
  const TaskNotificationAction({
    required this.action,
    required this.taskId,
    required this.title,
  });

  final String action;
  final String taskId;
  final String title;
}

class GeneralNotificationTap {
  const GeneralNotificationTap({
    required this.kind,
    required this.id,
    this.title = '',
    this.payload = const {},
  });

  final String kind;
  final String id;
  final String title;
  final Map<String, dynamic> payload;
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
  static final ValueNotifier<TaskNotificationAction?> taskAction =
      ValueNotifier<TaskNotificationAction?>(null);
  static final ValueNotifier<GeneralNotificationTap?> notificationTap =
      ValueNotifier<GeneralNotificationTap?>(null);
  static bool _ready = false;
  static Future<void>? _initFuture;

  @pragma('vm:entry-point')
  static void _backgroundResponse(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('[Reminder] receiver:fired id=${response.id}');
    }
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
    AndroidNotificationCategory category = AndroidNotificationCategory.reminder,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: category,
      icon: '@drawable/ic_stat_gochano',
      enableVibration: true,
      playSound: true,
      actions: actions,
    );
  }

  /// Converts a [DateTime] into a [tz.TZDateTime] aligned to the local
  /// timezone using wall-clock components. Reconstructing from wall-clock fields
  /// prevents accidental hour shifts caused by differing local/UTC representations.
  static tz.TZDateTime _toLocalTz(DateTime dt) {
    return tz.TZDateTime(
      tz.local,
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
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

  /// Open the OS exact-alarm settings screen for this app so the user can
  /// grant SCHEDULE_EXACT_ALARM special access. Falls back safely to
  /// [requestExactAlarmPermission] and application details settings.
  static Future<bool> openExactAlarmSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openExactAlarmSettings',
      );
      if (result == true) return true;
      return await requestExactAlarmPermission();
    } on MissingPluginException {
      return await requestExactAlarmPermission();
    } catch (_) {
      return await requestExactAlarmPermission();
    }
  }

  /// Open the OS Auto-start settings screen for this app (best-effort vendor
  /// target such as Transsion PhoneMaster AutoStart with app settings fallback).
  static Future<bool> openAutoStartSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAutoStartSettings');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns whether the app can schedule exact notifications on Android 12+ (API 31+).
  /// On older Android versions or non-Android platforms, returns true.
  static Future<bool> isExactAlarmPermissionGranted() async {
    try {
      await init();
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true;
      final canExact = await android.canScheduleExactNotifications() ?? false;
      if (kDebugMode) {
        debugPrint('[Reminder] exactAlarmAllowed=$canExact');
      }
      return canExact;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Reminder] isExactAlarmPermissionGranted fallback: $e');
      }
      return true;
    }
  }

  /// Request exact-alarm permission via Android system settings intent
  /// (Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM on Android 12+).
  /// Returns true if permission is granted or capability is supported.
  static Future<bool> requestExactAlarmPermission() async {
    try {
      await init();
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true;
      final requested = await android.requestExactAlarmsPermission() ?? false;
      final canExact = await android.canScheduleExactNotifications() ?? false;
      if (kDebugMode) {
        debugPrint('[Reminder] exactAlarmAllowed=$canExact');
      }
      return canExact || requested;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Reminder] requestExactAlarmPermission fallback: $e');
      }
      return true;
    }
  }

  static Future<void> init() {
    if (_ready) return Future.value();
    return _initFuture ??= _doInit();
  }

  static Future<void> _doInit() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(AppConfig.bangladeshTimeZone));
    } catch (_) {}

    try {
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

      if (android != null) {
        // Explicitly register notification channels with Importance.max so the OS
        // creates them with full sound, vibration, and heads-up banner display
        // before any background alarms fire.
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            kChannelRemindersId,
            kChannelRemindersName,
            description: kChannelRemindersDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            kChannelMedicineId,
            kChannelMedicineName,
            description: kChannelMedicineDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

        // Asynchronously request POST_NOTIFICATIONS (Android 13+) without blocking init.
        try {
          android.requestNotificationsPermission().catchError((_) => null);
        } catch (_) {}

        // Check exact-alarm capability on Android 12+.
        try {
          final canExact = await android
              .canScheduleExactNotifications()
              .timeout(const Duration(seconds: 2), onTimeout: () => false);
          if (kDebugMode) {
            debugPrint('[Reminder] exactAlarmAllowed=$canExact');
          }
        } catch (_) {
          // Safe to ignore on non-Android platforms or older API levels.
        }
      }

      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse != null) {
        _onResponse(launch!.notificationResponse!);
      }

      _ready = true;
      try {
        await LocalReminderStore.instance.init();
        await reconcileLocalReminders();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Reminder] Local reminder init/reconcile error: $e');
          debugPrint('[Reminder] Local reminder init error: $e');
        }
      }

      // Audit pending alarms surviving from previous sessions.
      if (kDebugMode) {
        try {
          final pending = await plugin.pendingNotificationRequests();
          debugPrint('[Reminder] pendingCount=${pending.length}');
          final notificationsOn =
              await android?.areNotificationsEnabled() ?? false;
          final exactOn =
              await android?.canScheduleExactNotifications() ?? false;
          debugPrint(
            '[TaskReminderRestoreAudit]'
            ' notificationsAllowed=$notificationsOn'
            ' exactCapability=$exactOn',
          );
        } catch (e) {
          debugPrint('[Reminder] pending audit failed: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Reminder] NotificationService.init caught: $e');
      }
    }
  }

  static void _onResponse(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('[Reminder] receiver:fired id=${response.id}');
      debugPrint(
        '[Reminder] receiver:fired id=${response.id} actionId=${response.actionId}',
      );
    }
    final payload = response.payload;
    final actionId = response.actionId?.trim();
    if (payload == null || payload.isEmpty) return;

    if (payload.startsWith('{')) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final kind = data['kind']?.toString() ?? '';

        if (kind == 'medicine') {
          if (actionId != null && actionId.isNotEmpty) {
            medicineAction.value = MedicineNotificationAction(
              action: actionId,
              medicineId: data['medicineId']?.toString() ?? '',
              medicineName: data['medicineName']?.toString() ?? '',
              hhmm: data['hhmm']?.toString() ?? '',
              quantityPerDose:
                  (data['quantityPerDose'] as num?)?.toDouble() ?? 1,
              unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
              unit: data['unit']?.toString() ?? 'tablet',
            );
          } else {
            notificationTap.value = GeneralNotificationTap(
              kind: 'medicine',
              id: data['medicineId']?.toString() ?? '',
              title: data['medicineName']?.toString() ?? '',
              payload: data,
            );
          }
          return;
        }

        if (kind == 'task' || kind == 'assignment') {
          final taskId = data['id']?.toString() ?? '';
          final title = data['title']?.toString() ?? '';
          if (actionId == 'done') {
            taskAction.value = TaskNotificationAction(
              action: 'done',
              taskId: taskId,
              title: title,
            );
          } else {
            notificationTap.value = GeneralNotificationTap(
              kind: kind,
              id: taskId,
              title: title,
              payload: data,
            );
          }
          return;
        }

        if (kind == 'expense_due' ||
            kind == 'commute_trip' ||
            kind == 'custom') {
          notificationTap.value = GeneralNotificationTap(
            kind: kind,
            id: data['id']?.toString() ?? '',
            title: data['title']?.toString() ?? '',
            payload: data,
          );
          return;
        }
      } catch (_) {
        // Fall through to legacy parsing
      }
    }

    try {
      // Legacy commute trip string payload
      if (payload.startsWith('commute_trip:')) {
        final tripId = payload.substring('commute_trip:'.length);
        notificationTap.value = GeneralNotificationTap(
          kind: 'commute_trip',
          id: tripId,
        );
        return;
      }

      // Legacy task payload
      if (actionId == 'done') {
        taskAction.value = TaskNotificationAction(
          action: 'done',
          taskId: payload,
          title: '',
        );
      } else {
        notificationTap.value = GeneralNotificationTap(
          kind: 'task',
          id: payload,
        );
      }
    } catch (_) {
      // Ignore malformed legacy payloads.
      return;
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
    final now = DateTime.now();
    // Items >= 30m past due are already missed; do not schedule past reminders.
    final missedAt = when.add(const Duration(minutes: 30));
    if (!missedAt.isAfter(now)) return;

    final scheduleMode = await _resolveScheduleMode();
    final isAssignment = type == 'assignment';
    final scheduledIds = <int>[];
    final scheduledSlots = <_ScheduledSlot>[];

    const taskCategory = AndroidNotificationCategory.reminder;

    for (final offset in _taskReminderOffsets) {
      final notifyAt = when.subtract(Duration(minutes: offset));
      if (!notifyAt.isAfter(now)) continue;

      final notifId = _taskNotificationId(taskId, offset);
      final slotLabel = offset > 0
          ? 'T-$offset'
          : offset == 0
          ? 'T'
          : 'T+${-offset}';

      try {
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
          scheduledDate: _toLocalTz(notifyAt),
          notificationDetails: NotificationDetails(
            android: _details(
              channelId: kChannelRemindersId,
              channelName: kChannelRemindersName,
              channelDescription: kChannelRemindersDesc,
              category: taskCategory,
              actions: const [
                AndroidNotificationAction(
                  'done',
                  'Done',
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
              ],
            ),
          ),
          androidScheduleMode: scheduleMode,
          payload: jsonEncode({
            'kind': isAssignment ? 'assignment' : 'task',
            'id': taskId,
            'title': title,
          }),
        );
      } on PlatformException catch (e) {
        if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
          await plugin.zonedSchedule(
            id: notifId,
            title: 'Gochano reminder',
            body: isAssignment
                ? '$title (in $offset mins)'
                : '$title (in $offset mins)',
            scheduledDate: _toLocalTz(notifyAt),
            notificationDetails: NotificationDetails(
              android: _details(
                channelId: kChannelRemindersId,
                channelName: kChannelRemindersName,
                channelDescription: kChannelRemindersDesc,
                category: taskCategory,
                actions: const [
                  AndroidNotificationAction(
                    'done',
                    'Done',
                    showsUserInterface: true,
                    cancelNotification: true,
                  ),
                ],
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: jsonEncode({
              'kind': isAssignment ? 'assignment' : 'task',
              'id': taskId,
              'title': title,
            }),
          );
        } else {
          if (kDebugMode) {
            debugPrint('[TaskReminderSchedule] zonedSchedule failed: $e');
          }
        }
      }

      scheduledIds.add(notifId);
      scheduledSlots.add(
        _ScheduledSlot(
          slotLabel: slotLabel,
          notificationId: notifId,
          scheduledAt: notifyAt,
        ),
      );
      if (kDebugMode) {
        debugPrint('[Reminder] schedule id=$notifId type=$type at=$notifyAt');
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

    // Persist local reminder for offline availability and Notification Center
    try {
      await LocalReminderStore.instance.save(
        LocalReminder(
          id: 'task_$taskId',
          ownerItemId: taskId,
          type: isAssignment
              ? LocalReminderType.assignment
              : LocalReminderType.task,
          title: title,
          body: isAssignment
              ? GochanoLanguage.text(
                  'Assignment due at scheduled time',
                  'নির্ধারিত সময়ে অ্যাসাইনমেন্ট জমা দিন',
                )
              : GochanoLanguage.text(
                  'Task due at scheduled time',
                  'নির্ধারিত সময়ে কাজটি সম্পন্ন করুন',
                ),
          scheduledAt: when,
          offsets: _taskReminderOffsets,
          notificationIds: scheduledIds,
          recurrence: LocalReminderRecurrence.none,
          status: LocalReminderStatus.pending,
          payload: {'id': taskId, 'title': title, 'isAssignment': isAssignment},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TaskReminderSchedule] local store save failed: $e');
      }
    }

    await _verifyAndDiagnoseRegistration(
      entityType: 'task',
      entityId: taskId,
      slots: scheduledSlots,
      scheduleMode: scheduleMode,
    );
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
      final notifId = _taskNotificationId(taskId, offset);
      await plugin.cancel(id: notifId);
      if (kDebugMode) {
        debugPrint('[Reminder] cancel id=$notifId');
      }
    }
    if (when == null) {
      await LocalReminderStore.instance.updateStatusByOwnerItemId(
        taskId,
        LocalReminderStatus.cancelled,
      );
      return;
    }
    final missedAt = when.add(const Duration(minutes: 30));
    if (!missedAt.isAfter(DateTime.now())) {
      await LocalReminderStore.instance.updateStatusByOwnerItemId(
        taskId,
        LocalReminderStatus.missed,
      );
      return;
    }
    await scheduleTask(taskId: taskId, title: title, when: when, type: type);
  }

  static const List<int> _medicineFollowUpOffsets = [0, 30, 60, 90, 120];
  static Future<void> cancelTask(String taskId) async {
    await init();
    if (kDebugMode) {
      debugPrint('[TaskReminderSchedule] cancelTask taskId=$taskId');
    }
    for (final offset in _taskReminderOffsets) {
      final notifId = _taskNotificationId(taskId, offset);
      await plugin.cancel(id: notifId);
      if (kDebugMode) {
        debugPrint('[Reminder] cancel id=$notifId');
      }
    }
    await LocalReminderStore.instance.updateStatusByOwnerItemId(
      taskId,
      LocalReminderStatus.cancelled,
    );
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
    final scheduledSlots = <_ScheduledSlot>[
      _ScheduledSlot(
        slotLabel: 'T (daily recurring)',
        notificationId: _medicineNotificationId(medicineId, hhmm, 0),
        scheduledAt: next,
      ),
    ];

    final baseId = _medicineNotificationId(medicineId, hhmm, 0);
    // Base dose at scheduled time (offset 0), repeats daily
    try {
      await plugin.zonedSchedule(
        id: baseId,
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
    } on PlatformException catch (e) {
      if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        await plugin.zonedSchedule(
          id: baseId,
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
      } else {
        if (kDebugMode) {
          debugPrint('[MedicineSchedule] zonedSchedule base dose failed: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint('[Reminder] schedule id=$baseId type=medicine at=$next');
    }

    // Follow-ups at 30, 60, 90, 120 minutes
    for (final offset in _medicineFollowUpOffsets.skip(1)) {
      final followUpTime = next.add(Duration(minutes: offset));
      final notifId = _medicineNotificationId(medicineId, hhmm, offset);
      scheduledSlots.add(
        _ScheduledSlot(
          slotLabel: 'T+$offset (follow-up)',
          notificationId: notifId,
          scheduledAt: followUpTime,
        ),
      );
      try {
        await plugin.zonedSchedule(
          id: notifId,
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
      } on PlatformException catch (e) {
        if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
          await plugin.zonedSchedule(
            id: notifId,
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
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
        } else {
          if (kDebugMode) {
            debugPrint('[MedicineSchedule] zonedSchedule follow-up failed: $e');
          }
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[Reminder] schedule id=$notifId type=medicine at=$followUpTime',
        );
      }
    }

    // Persist local reminder for offline availability and Notification Center
    try {
      await LocalReminderStore.instance.save(
        LocalReminder(
          id: 'medicine_${medicineId}_$hhmm',
          ownerItemId: medicineId,
          type: LocalReminderType.medicine,
          title: medicineName,
          body: instruction.trim().isEmpty
              ? '$quantityPerDose $unit at $hhmm'
              : '$instruction ($hhmm)',
          scheduledAt: next,
          offsets: _medicineFollowUpOffsets,
          notificationIds: scheduledSlots.map((s) => s.notificationId).toList(),
          recurrence: LocalReminderRecurrence.daily,
          status: LocalReminderStatus.pending,
          payload: {
            'medicineId': medicineId,
            'medicineName': medicineName,
            'hhmm': hhmm,
            'instruction': instruction,
            'quantityPerDose': quantityPerDose,
            'unitPrice': unitPrice,
            'unit': unit,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MedicineSchedule] local store save failed: $e');
      }
    }

    await _verifyAndDiagnoseRegistration(
      entityType: 'medicine',
      entityId: '$medicineId:$hhmm',
      slots: scheduledSlots,
      scheduleMode: scheduleMode,
    );
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
      final notifId = _medicineNotificationId(medicineId, hhmm, offset);
      await plugin.cancel(id: notifId);
      if (kDebugMode) {
        debugPrint('[Reminder] cancel id=$notifId');
      }
    }
  }

  static Future<void> cancelMedicineTimes(
    String medicineId,
    Iterable<String> times,
  ) async {
    await init();
    for (final time in times) {
      for (final offset in _medicineFollowUpOffsets) {
        final notifId = _medicineNotificationId(medicineId, time, offset);
        await plugin.cancel(id: notifId);
        if (kDebugMode) {
          debugPrint('[Reminder] cancel id=$notifId');
        }
      }
      await LocalReminderStore.instance.updateStatus(
        'medicine_${medicineId}_$time',
        LocalReminderStatus.cancelled,
      );
    }
  }

  /// Cancels all existing local reminders and notifications for [medicineId]
  /// purely from the local device store, requiring zero network access.
  static Future<void> cancelMedicineByOwnerId(String medicineId) async {
    await init();
    final all = LocalReminderStore.instance.getReconcilableReminders();
    for (final reminder in all) {
      if (reminder.type == LocalReminderType.medicine &&
          reminder.ownerItemId == medicineId) {
        final hhmm = reminder.payload['hhmm']?.toString() ?? '';
        if (hhmm.isNotEmpty) {
          for (final offset in _medicineFollowUpOffsets) {
            final notifId = _medicineNotificationId(medicineId, hhmm, offset);
            await plugin.cancel(id: notifId);
          }
        }
      }
    }
    await LocalReminderStore.instance.updateStatusByOwnerItemId(
      medicineId,
      LocalReminderStatus.cancelled,
    );
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
  ) => _stableStringId('community_${groupId}_${projectId}_${taskId}_$userId');

  static int _legacyCommunityTaskReminderId(
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

    final scheduleMode = await _resolveScheduleMode();
    final notifId = _communityTaskReminderId(
      groupId,
      projectId,
      taskId,
      userId,
    );

    try {
      await plugin.zonedSchedule(
        id: notifId,
        title: 'Gochano reminder',
        body: title,
        scheduledDate: _toLocalTz(when),
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
    } on PlatformException catch (e) {
      if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        await plugin.zonedSchedule(
          id: notifId,
          title: 'Gochano reminder',
          body: title,
          scheduledDate: _toLocalTz(when),
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
      } else {
        if (kDebugMode) {
          debugPrint('[CommunityTaskSchedule] zonedSchedule failed: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[Reminder] schedule id=$notifId type=community_task at=$when',
      );
    }

    await _verifyAndDiagnoseRegistration(
      entityType: 'community_task',
      entityId: taskId,
      slots: [
        _ScheduledSlot(
          slotLabel: 'T',
          notificationId: notifId,
          scheduledAt: when,
        ),
      ],
      scheduleMode: scheduleMode,
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
    final primaryId = _communityTaskReminderId(
      groupId,
      projectId,
      taskId,
      userId,
    );
    final legacyId = _legacyCommunityTaskReminderId(
      groupId,
      projectId,
      taskId,
      userId,
    );
    await plugin.cancel(id: primaryId);
    await plugin.cancel(id: legacyId);
    if (kDebugMode) {
      debugPrint('[Reminder] cancel id=$primaryId');
      debugPrint('[Reminder] cancel id=$legacyId');
    }
    if (when == null || !when.isAfter(DateTime.now())) return;
    await scheduleCommunityTaskReminder(
      groupId: groupId,
      projectId: projectId,
      taskId: taskId,
      userId: userId,
      title: title,
      when: when,
    );
  }

  static Future<void> cancelCommunityTaskReminder({
    required String groupId,
    required String projectId,
    required String taskId,
    required String userId,
  }) async {
    await init();
    final primaryId = _communityTaskReminderId(
      groupId,
      projectId,
      taskId,
      userId,
    );
    final legacyId = _legacyCommunityTaskReminderId(
      groupId,
      projectId,
      taskId,
      userId,
    );
    await plugin.cancel(id: primaryId);
    await plugin.cancel(id: legacyId);
    if (kDebugMode) {
      debugPrint('[Reminder] cancel id=$primaryId');
      debugPrint('[Reminder] cancel id=$legacyId');
    }
  }

  /// Resolves the safe scheduling mode on Android.
  ///
  /// Uses [AndroidScheduleMode.exactAllowWhileIdle] when exact-alarm capability is
  /// granted/supported, falling back to [AndroidScheduleMode.inexactAllowWhileIdle].
  static Future<AndroidScheduleMode> _resolveScheduleMode() async {
    try {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canExact =
          await android?.canScheduleExactNotifications().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          ) ??
          false;
      final notificationsAllowed =
          await android?.areNotificationsEnabled().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          ) ??
          false;
      if (kDebugMode) {
        debugPrint('[Reminder] exactAlarmAllowed=$canExact');
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

  // ---------------------------------------------------------------------------
  // Planned Commute Trip Reminders (user-selected single reminder)
  // ---------------------------------------------------------------------------

  /// Deterministic notification id for the user-selected reminder lead time.
  static int _commuteTripUserReminderId(String tripId, int reminderMinutes) {
    return _stableStringId('commute_reminder_${tripId}_$reminderMinutes');
  }

  /// Schedule exactly ONE notification at [reminderMinutes] before departure.
  /// If [reminderMinutes] <= 0, no notification is scheduled.
  static Future<void> scheduleCommuteTripReminder({
    required String tripId,
    required String title,
    required int reminderMinutes,
    DateTime? departureTime,
  }) async {
    await init();
    if (reminderMinutes <= 0 || departureTime == null) return;

    final scheduleMode = await _resolveScheduleMode();
    final now = DateTime.now();
    final scheduledSlots = <_ScheduledSlot>[];

    final notifyAt = departureTime.subtract(Duration(minutes: reminderMinutes));
    if (!notifyAt.isAfter(now)) return;

    final notifId = _commuteTripUserReminderId(tripId, reminderMinutes);

    try {
      await plugin.zonedSchedule(
        id: notifId,
        title: 'Commute reminder',
        body: '$title ($reminderMinutes min before departure)',
        scheduledDate: _toLocalTz(notifyAt),
        notificationDetails: NotificationDetails(
          android: _details(
            channelId: kChannelRemindersId,
            channelName: kChannelRemindersName,
            channelDescription: kChannelRemindersDesc,
          ),
        ),
        androidScheduleMode: scheduleMode,
        payload: jsonEncode({
          'kind': 'commute_trip',
          'id': tripId,
          'title': title,
          'reminderMinutes': reminderMinutes,
          'departureTime': departureTime.toIso8601String(),
        }),
      );
    } on PlatformException catch (e) {
      if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        await plugin.zonedSchedule(
          id: notifId,
          title: 'Commute reminder',
          body: '$title ($reminderMinutes min before departure)',
          scheduledDate: _toLocalTz(notifyAt),
          notificationDetails: NotificationDetails(
            android: _details(
              channelId: kChannelRemindersId,
              channelName: kChannelRemindersName,
              channelDescription: kChannelRemindersDesc,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: jsonEncode({
            'kind': 'commute_trip',
            'id': tripId,
            'title': title,
            'reminderMinutes': reminderMinutes,
            'departureTime': departureTime.toIso8601String(),
          }),
        );
      } else {
        if (kDebugMode) {
          debugPrint('[CommuteTripSchedule] zonedSchedule failed: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[Reminder] schedule id=$notifId type=commute_trip at=$notifyAt',
      );
    }

    scheduledSlots.add(
      _ScheduledSlot(
        slotLabel: 'T-$reminderMinutes',
        notificationId: notifId,
        scheduledAt: notifyAt,
      ),
    );

    // Persist local reminder for offline availability and Notification Center
    try {
      await LocalReminderStore.instance.save(
        LocalReminder(
          id: 'trip_$tripId',
          ownerItemId: tripId,
          type: LocalReminderType.commuteTrip,
          title: title,
          body: '$reminderMinutes min before departure',
          scheduledAt: notifyAt,
          offsets: [reminderMinutes],
          notificationIds: [notifId],
          recurrence: LocalReminderRecurrence.none,
          status: LocalReminderStatus.pending,
          payload: {
            'tripId': tripId,
            'title': title,
            'departureTime': departureTime.toIso8601String(),
            'reminderMinutes': reminderMinutes,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CommuteTripSchedule] local store save failed: $e');
      }
    }

    await _verifyAndDiagnoseRegistration(
      entityType: 'commute_trip',
      entityId: tripId,
      slots: scheduledSlots,
      scheduleMode: scheduleMode,
    );
  }

  static Future<void> rescheduleCommuteTripReminder({
    required String tripId,
    required String title,
    required int reminderMinutes,
    DateTime? departureTime,
  }) async {
    await init();
    await cancelCommuteTripReminder(tripId);
    if (reminderMinutes > 0 && departureTime != null) {
      await scheduleCommuteTripReminder(
        tripId: tripId,
        title: title,
        reminderMinutes: reminderMinutes,
        departureTime: departureTime,
      );
    }
  }

  static Future<void> cancelCommuteTripReminder(String tripId) async {
    await init();
    // Cancel user-selected reminders for all known lead-time options.
    for (final mins in [10, 30, 60]) {
      final notifId = _commuteTripUserReminderId(tripId, mins);
      await plugin.cancel(id: notifId);
      if (kDebugMode) {
        debugPrint('[Reminder] cancel id=$notifId');
      }
    }
    // Also cancel any legacy offset-based IDs from previous versions.
    for (final offset in [60, 30, 10]) {
      final notifId = _stableStringId('commute_${tripId}_$offset');
      await plugin.cancel(id: notifId);
      if (kDebugMode) {
        debugPrint('[Reminder] cancel id=$notifId');
      }
    }
    // Cancel legacy single-ID format.
    final singleId = _stableStringId('commute_trip_$tripId');
    await plugin.cancel(id: singleId);
    if (kDebugMode) {
      debugPrint('[Reminder] cancel id=$singleId');
    }
    await LocalReminderStore.instance.updateStatusByOwnerItemId(
      tripId,
      LocalReminderStatus.cancelled,
    );
  }

  // ---------------------------------------------------------------------------
  // Expense / Due Date Reminders (Dena / Pawna)
  // ---------------------------------------------------------------------------

  static int _expenseDueNotificationId(
    String itemId, [
    int offsetMinutes = 0,
  ]) => _stableStringId('due_${itemId}_$offsetMinutes');

  @visibleForTesting
  static int debugExpenseDueNotificationId(
    String itemId, [
    int offsetMinutes = 0,
  ]) => _expenseDueNotificationId(itemId, offsetMinutes);

  static Future<void> scheduleExpenseDueReminder({
    required String itemId,
    required String personName,
    required double amount,
    required String type,
    required DateTime dueDate,
  }) async {
    await init();
    final now = DateTime.now();
    // Set 09:00 AM on due date if user only specified the day
    final scheduledAt = (dueDate.hour == 0 && dueDate.minute == 0)
        ? DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0)
        : dueDate;

    if (!scheduledAt.isAfter(now)) return;

    final scheduleMode = await _resolveScheduleMode();
    final notifId = _expenseDueNotificationId(itemId, 0);

    final isLend = type == 'lend';
    final title = isLend
        ? GochanoLanguage.text(
            'Payment due: $personName',
            'টাকা পাওয়ার তারিখ: $personName',
          )
        : GochanoLanguage.text(
            'Payment due to: $personName',
            'টাকা পরিশোধের তারিখ: $personName',
          );
    final body = isLend
        ? GochanoLanguage.text(
            'Collect ৳${amount.toStringAsFixed(0)} from $personName',
            '$personName-এর থেকে ৳${amount.toStringAsFixed(0)} সংগ্রহ করুন',
          )
        : GochanoLanguage.text(
            'Pay ৳${amount.toStringAsFixed(0)} to $personName',
            '$personName-কে ৳${amount.toStringAsFixed(0)} পরিশোধ করুন',
          );

    final payload = jsonEncode({
      'kind': 'expense_due',
      'id': itemId,
      'personName': personName,
      'amount': amount,
      'dueType': type,
      'title': title,
    });

    try {
      await plugin.zonedSchedule(
        id: notifId,
        title: title,
        body: body,
        scheduledDate: _toLocalTz(scheduledAt),
        notificationDetails: NotificationDetails(
          android: _details(
            channelId: kChannelRemindersId,
            channelName: kChannelRemindersName,
            channelDescription: kChannelRemindersDesc,
          ),
        ),
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
    } on PlatformException catch (e) {
      if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        await plugin.zonedSchedule(
          id: notifId,
          title: title,
          body: body,
          scheduledDate: _toLocalTz(scheduledAt),
          notificationDetails: NotificationDetails(
            android: _details(
              channelId: kChannelRemindersId,
              channelName: kChannelRemindersName,
              channelDescription: kChannelRemindersDesc,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } else {
        if (kDebugMode) {
          debugPrint('[ExpenseDueSchedule] zonedSchedule failed: $e');
        }
      }
    }

    try {
      await LocalReminderStore.instance.save(
        LocalReminder(
          id: 'due_$itemId',
          ownerItemId: itemId,
          type: LocalReminderType.expenseDue,
          title: title,
          body: body,
          scheduledAt: scheduledAt,
          offsets: const [0],
          notificationIds: [notifId],
          recurrence: LocalReminderRecurrence.none,
          status: LocalReminderStatus.pending,
          payload: {
            'itemId': itemId,
            'personName': personName,
            'amount': amount,
            'dueType': type,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ExpenseDueSchedule] local store save failed: $e');
      }
    }
  }

  static Future<void> cancelExpenseDueReminder(String itemId) async {
    await init();
    final notifId = _expenseDueNotificationId(itemId, 0);
    await plugin.cancel(id: notifId);
    await LocalReminderStore.instance.updateStatusByOwnerItemId(
      itemId,
      LocalReminderStatus.cancelled,
    );
  }

  // ---------------------------------------------------------------------------
  // Simple Custom Reminders (lightweight)
  // ---------------------------------------------------------------------------

  static int _customReminderNotificationId(String reminderId) =>
      _stableStringId('custom_$reminderId');

  @visibleForTesting
  static int debugCustomReminderNotificationId(String reminderId) =>
      _customReminderNotificationId(reminderId);

  static Future<String> scheduleCustomReminder({
    String? id,
    required String title,
    String note = '',
    required DateTime when,
  }) async {
    if (kDebugMode) {
      debugPrint('[OfflineSave][Custom] start');
    }
    await init();
    final reminderId = id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    if (!when.isAfter(now)) return reminderId;

    final scheduleMode = await _resolveScheduleMode();
    final notifId = _customReminderNotificationId(reminderId);

    // 1. Persist local reminder in local manifest store first for instant offline readiness
    try {
      await LocalReminderStore.instance.save(
        LocalReminder(
          id: reminderId,
          ownerItemId: reminderId,
          type: LocalReminderType.custom,
          title: title,
          body: note,
          scheduledAt: when,
          offsets: const [0],
          notificationIds: [notifId],
          recurrence: LocalReminderRecurrence.none,
          status: LocalReminderStatus.pending,
          payload: {'id': reminderId, 'title': title, 'note': note},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (kDebugMode) {
        debugPrint('[OfflineSave][Custom] local reminder persisted');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineSave][Custom] local store save failed: $e');
      }
    }

    final payload = jsonEncode({
      'kind': 'custom',
      'id': reminderId,
      'title': title,
      'note': note,
    });

    // 2. Schedule OS alarm with exact / inexact fallback
    try {
      await plugin.zonedSchedule(
        id: notifId,
        title: 'Gochano reminder',
        body: note.trim().isEmpty ? title : '$title — $note',
        scheduledDate: _toLocalTz(when),
        notificationDetails: NotificationDetails(
          android: _details(
            channelId: kChannelRemindersId,
            channelName: kChannelRemindersName,
            channelDescription: kChannelRemindersDesc,
          ),
        ),
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
      if (kDebugMode) {
        debugPrint('[OfflineSave][Custom] alarm scheduled');
      }
    } on PlatformException catch (e) {
      if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        try {
          await plugin.zonedSchedule(
            id: notifId,
            title: 'Gochano reminder',
            body: note.trim().isEmpty ? title : '$title — $note',
            scheduledDate: _toLocalTz(when),
            notificationDetails: NotificationDetails(
              android: _details(
                channelId: kChannelRemindersId,
                channelName: kChannelRemindersName,
                channelDescription: kChannelRemindersDesc,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
          if (kDebugMode) {
            debugPrint(
              '[OfflineSave][Custom] alarm scheduled (inexact fallback)',
            );
          }
        } catch (_) {}
      } else {
        if (kDebugMode) {
          debugPrint('[CustomReminderSchedule] zonedSchedule failed: $e');
        }
      }
    }

    try {
      await LocalReminderStore.instance.save(
        LocalReminder(
          id: reminderId,
          ownerItemId: reminderId,
          type: LocalReminderType.custom,
          title: title,
          body: note,
          scheduledAt: when,
          offsets: const [0],
          notificationIds: [notifId],
          recurrence: LocalReminderRecurrence.none,
          status: LocalReminderStatus.pending,
          payload: {'id': reminderId, 'title': title, 'note': note},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CustomReminderSchedule] local store save failed: $e');
        debugPrint('[CustomReminderSchedule] zonedSchedule error: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('[OfflineSave][Custom] ui complete');
    }

    return reminderId;
  }

  static Future<void> cancelCustomReminder(String reminderId) async {
    await init();
    final notifId = _customReminderNotificationId(reminderId);
    await plugin.cancel(id: notifId);
    await LocalReminderStore.instance.updateStatus(
      reminderId,
      LocalReminderStatus.cancelled,
    );
  }

  @visibleForTesting
  static int debugCommuteTripNotificationId(
    String tripId, [
    int reminderMinutes = 0,
  ]) {
    if (reminderMinutes <= 0) {
      return _stableStringId('commute_trip_$tripId');
    }
    return _commuteTripUserReminderId(tripId, reminderMinutes);
  }

  // ---------------------------------------------------------------------------
  // Diagnostics & Registration Verification
  // ---------------------------------------------------------------------------

  static Future<void> _verifyAndDiagnoseRegistration({
    required String entityType,
    required String entityId,
    required List<_ScheduledSlot> slots,
    required AndroidScheduleMode scheduleMode,
  }) async {
    if (!kDebugMode || slots.isEmpty) return;
    try {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final pending = await plugin.pendingNotificationRequests();
      final pendingIds = pending.map((r) => r.id).toSet();
      final expectedIds = slots.map((s) => s.notificationId).toSet();
      final missing = expectedIds.difference(pendingIds);
      final notificationsOn = await android?.areNotificationsEnabled() ?? false;
      final exactOn = await android?.canScheduleExactNotifications() ?? false;

      debugPrint(
        '[ReminderRegistrationDiagnostic] entityType=$entityType'
        ' entityId=$entityId'
        ' totalSlots=${slots.length}'
        ' verifiedInOs=${slots.length - missing.length}'
        ' missingFromOs=${missing.length}'
        ' exactCapability=$exactOn'
        ' notificationsAllowed=$notificationsOn'
        ' scheduleMode=$scheduleMode',
      );
    } catch (e) {
      debugPrint('[ReminderRegistrationDiagnostic] audit failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Startup Reconciliation
  // ---------------------------------------------------------------------------

  /// Idempotent startup reconciliation to ensure AlarmManager/OS scheduled
  /// alarms match active Firestore state without clearing unaffected alarms.
  static Future<void> reconcileReminders({
    List<Map<String, dynamic>>? tasks,
    List<Map<String, dynamic>>? medicines,
    List<Map<String, dynamic>>? commuteTrips,
  }) async {
    await init();
    if (kDebugMode) {
      debugPrint('[Reminder] reconcile:start');
    }
    try {
      final pending = await plugin.pendingNotificationRequests();
      if (kDebugMode) {
        debugPrint('[Reminder] pendingCount=${pending.length}');
      }
      final pendingIds = pending.map((r) => r.id).toSet();
      final now = DateTime.now();

      // 1. Reconcile Tasks
      if (tasks != null) {
        for (final task in tasks) {
          final id = task['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final isCompleted = task['completed'] == true;
          final dueAt = task['dueAt'] is DateTime
              ? task['dueAt'] as DateTime
              : (task['dueAt'] != null
                    ? DateTime.tryParse(task['dueAt'].toString())
                    : null);
          final title = task['title']?.toString() ?? '';
          final type = task['type']?.toString() ?? 'task';

          if (isCompleted ||
              dueAt == null ||
              !dueAt.add(const Duration(minutes: 30)).isAfter(now)) {
            // Cancel stale/completed/missed task notifications
            for (final offset in _taskReminderOffsets) {
              final notifId = _taskNotificationId(id, offset);
              if (pendingIds.contains(notifId)) {
                await plugin.cancel(id: notifId);
                if (kDebugMode) {
                  debugPrint('[Reminder] cancel id=$notifId');
                }
                pendingIds.remove(notifId);
              }
            }
          } else {
            // Check if any future offset is missing from OS
            var hasMissingFutureSlot = false;
            for (final offset in _taskReminderOffsets) {
              final notifyAt = dueAt.subtract(Duration(minutes: offset));
              if (notifyAt.isAfter(now)) {
                final notifId = _taskNotificationId(id, offset);
                if (!pendingIds.contains(notifId)) {
                  hasMissingFutureSlot = true;
                  break;
                }
              }
            }
            if (hasMissingFutureSlot) {
              await scheduleTask(
                taskId: id,
                title: title,
                when: dueAt,
                type: type,
              );
            }
          }
        }
      }

      // 2. Reconcile Medicines
      if (medicines != null) {
        for (final med in medicines) {
          final id = med['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final isActive = med['active'] != false && med['paused'] != true;
          final times =
              (med['times'] as List<dynamic>?)
                  ?.map((t) => t.toString())
                  .toList() ??
              const <String>[];
          final name = med['name']?.toString() ?? '';

          if (!isActive) {
            for (final t in times) {
              for (final off in _medicineFollowUpOffsets) {
                final notifId = _medicineNotificationId(id, t, off);
                if (pendingIds.contains(notifId)) {
                  await plugin.cancel(id: notifId);
                  if (kDebugMode) {
                    debugPrint('[Reminder] cancel id=$notifId');
                  }
                  pendingIds.remove(notifId);
                }
              }
            }
          } else {
            for (final t in times) {
              final baseId = _medicineNotificationId(id, t, 0);
              if (!pendingIds.contains(baseId)) {
                await scheduleDailyMedicine(
                  medicineId: id,
                  medicineName: name,
                  hhmm: t,
                  instruction: med['instruction']?.toString() ?? '',
                  quantityPerDose:
                      (med['quantityPerDose'] as num?)?.toDouble() ?? 1,
                  unitPrice: (med['unitPrice'] as num?)?.toDouble() ?? 0,
                  unit: med['unit']?.toString() ?? 'tablet',
                );
              }
            }
          }
        }
      }

      // 3. Reconcile Commute Trips (single user-selected reminder)
      if (commuteTrips != null) {
        for (final trip in commuteTrips) {
          final id = trip['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final departure = trip['departureTime'] is DateTime
              ? trip['departureTime'] as DateTime
              : (trip['departureTime'] != null
                    ? DateTime.tryParse(trip['departureTime'].toString())
                    : null);
          final destination = trip['destinationName']?.toString() ?? '';
          final reminderMinutes =
              (trip['reminderMinutes'] as num?)?.toInt() ?? 0;
          final completed = trip['completed'] == true;

          if (completed ||
              departure == null ||
              !departure.isAfter(now) ||
              reminderMinutes <= 0) {
            // Cancel reminders for stale/past/disabled/completed trips
            await cancelCommuteTripReminder(id);
            for (final mins in [10, 30, 60]) {
              pendingIds.remove(
                _stableStringId('commute_reminder_${id}_$mins'),
              );
            }
          } else {
            // Upcoming trip: check if the user-selected reminder is present
            final expectedId = _commuteTripUserReminderId(id, reminderMinutes);
            if (!pendingIds.contains(expectedId)) {
              await scheduleCommuteTripReminder(
                tripId: id,
                title: 'Trip to $destination',
                reminderMinutes: reminderMinutes,
                departureTime: departure,
              );
            }
          }
        }
      }
      if (kDebugMode) {
        debugPrint('[Reminder] reconcile:end');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService.reconcileReminders] error: $e');
      }
    }
  }

  /// Automatically pulls active tasks, medicines, and planned trips for the current
  /// authenticated user and reconciles OS-level scheduled notifications with active state.
  static Future<void> reconcileFromFirestore() async {
    final uid = FirestoreService.uid;
    if (uid == null) return;
    try {
      final tasksSnap = await FirestoreService.db
          .collection('tasks')
          .where('ownerId', isEqualTo: uid)
          .limit(100)
          .get();
      final tasks = tasksSnap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      final medsSnap = await FirestoreService.db
          .collection('medicines')
          .where('ownerId', isEqualTo: uid)
          .limit(50)
          .get();
      final meds = medsSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      final tripsSnap = await FirestoreService.db
          .collection('planned_trips')
          .where('ownerId', isEqualTo: uid)
          .limit(50)
          .get();
      final trips = tripsSnap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      await reconcileReminders(
        tasks: tasks,
        medicines: meds,
        commuteTrips: trips,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService.reconcileFromFirestore] error: $e');
      }
    }
  }

  /// Idempotent startup and post-reboot reconciliation to ensure AlarmManager / OS
  /// scheduled alarms match device-local pending reminders without requiring network access.
  static Future<void> reconcileLocalReminders() async {
    await init();
    try {
      final pending = await plugin.pendingNotificationRequests();
      final pendingIds = pending.map((r) => r.id).toSet();
      final localReminders = LocalReminderStore.instance
          .getReconcilableReminders();
      final now = DateTime.now();

      for (final reminder in localReminders) {
        if (reminder.type == LocalReminderType.task ||
            reminder.type == LocalReminderType.assignment) {
          var missing = false;
          for (final offset in reminder.offsets) {
            final notifyAt = reminder.scheduledAt.subtract(
              Duration(minutes: offset),
            );
            if (notifyAt.isAfter(now)) {
              final notifId = _taskNotificationId(reminder.ownerItemId, offset);
              if (!pendingIds.contains(notifId)) {
                missing = true;
                break;
              }
            }
          }
          if (missing) {
            await scheduleTask(
              taskId: reminder.ownerItemId,
              title: reminder.title,
              when: reminder.scheduledAt,
              type: reminder.type == LocalReminderType.assignment
                  ? 'assignment'
                  : 'task',
            );
          }
        } else if (reminder.type == LocalReminderType.medicine) {
          final hhmm = reminder.payload['hhmm']?.toString();
          if (hhmm != null) {
            final baseId = _medicineNotificationId(
              reminder.ownerItemId,
              hhmm,
              0,
            );
            if (!pendingIds.contains(baseId)) {
              await scheduleDailyMedicine(
                medicineId: reminder.ownerItemId,
                medicineName: reminder.title,
                hhmm: hhmm,
                instruction: reminder.payload['instruction']?.toString() ?? '',
                quantityPerDose:
                    (reminder.payload['quantityPerDose'] as num?)?.toDouble() ??
                    1,
                unitPrice:
                    (reminder.payload['unitPrice'] as num?)?.toDouble() ?? 0,
                unit: reminder.payload['unit']?.toString() ?? 'tablet',
              );
            }
          }
        } else if (reminder.type == LocalReminderType.commuteTrip) {
          final departureStr = reminder.payload['departureTime']?.toString();
          final departure = departureStr != null
              ? DateTime.tryParse(departureStr)
              : null;
          final mins =
              (reminder.payload['reminderMinutes'] as num?)?.toInt() ?? 0;
          if (departure != null && departure.isAfter(now) && mins > 0) {
            final expectedId = _commuteTripUserReminderId(
              reminder.ownerItemId,
              mins,
            );
            if (!pendingIds.contains(expectedId)) {
              await scheduleCommuteTripReminder(
                tripId: reminder.ownerItemId,
                title: reminder.title,
                reminderMinutes: mins,
                departureTime: departure,
              );
            }
          }
        } else if (reminder.type == LocalReminderType.expenseDue) {
          final notifId = _expenseDueNotificationId(reminder.ownerItemId, 0);
          if (!pendingIds.contains(notifId) &&
              reminder.scheduledAt.isAfter(now)) {
            await scheduleExpenseDueReminder(
              itemId: reminder.ownerItemId,
              personName:
                  reminder.payload['personName']?.toString() ?? reminder.title,
              amount: (reminder.payload['amount'] as num?)?.toDouble() ?? 0,
              type: reminder.payload['dueType']?.toString() ?? 'lend',
              dueDate: reminder.scheduledAt,
            );
          }
        } else if (reminder.type == LocalReminderType.custom) {
          final notifId = _customReminderNotificationId(reminder.id);
          if (!pendingIds.contains(notifId) &&
              reminder.scheduledAt.isAfter(now)) {
            await scheduleCustomReminder(
              id: reminder.id,
              title: reminder.title,
              note: reminder.body,
              when: reminder.scheduledAt,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService.reconcileLocalReminders] error: $e');
      }
    }
  }
}

class _ScheduledSlot {
  const _ScheduledSlot({
    required this.slotLabel,
    required this.notificationId,
    required this.scheduledAt,
  });

  final String slotLabel;
  final int notificationId;
  final DateTime scheduledAt;
}
