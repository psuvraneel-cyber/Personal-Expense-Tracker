import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Wraps [FlutterLocalNotificationsPlugin] with:
///  • Android 13+ runtime permission request
///  • Plugin-level permission request (required by flutter_local_notifications v17+)
///  • iOS / macOS initialisation
///  • Silent-fail guard replaced with queuing patterns for instant and scheduled notifications
///  • Collision-safe notification IDs
///  • Lock screen privacy (NotificationVisibility.private)
///  • Central notification preference gate per category
///  • Tap payload deep linking (warm + cold start)
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  /// Android notification group key for high-importance alerts (budget, anomaly, bill).
  static const String alertsGroupKey = 'com.pet.tracker.ALERTS';

  /// Notification ID reserved for the Android alerts group summary notification.
  static const int alertsSummaryNotificationId = 999999;

  /// Rolling time window within which alerts are tracked for group summary thresholding.
  static const Duration groupSummaryRollingWindow = Duration(seconds: 30);

  /// Alert count threshold in [groupSummaryRollingWindow] that triggers a group summary notification.
  static const int groupSummaryThreshold = 2;

  static final List<({
    DateTime timestamp,
    String title,
    String body,
    NotificationCategory category,
  })> _recentAlertHistory = [];

  @visibleForTesting
  static void resetForTest() {
    _isInitialized = false;
    _pending.clear();
    _pendingScheduled.clear();
    _recentAlertHistory.clear();
    _initialPayload = null;
    selectNotificationNotifier.value = null;
  }

  @visibleForTesting
  static int get recentAlertHistoryCount => _recentAlertHistory.length;

  @visibleForTesting
  static int get pendingCount => _pending.length;

  @visibleForTesting
  static int get pendingScheduledCount => _pendingScheduled.length;

  /// Notifier for current notification permission status.
  static final ValueNotifier<PermissionStatus> permissionNotifier =
      ValueNotifier<PermissionStatus>(PermissionStatus.granted);

  /// Notifier updated when a notification tap is received.
  static final ValueNotifier<String?> selectNotificationNotifier =
      ValueNotifier<String?>(null);

  static String? _initialPayload;
  static String? get initialPayload => _initialPayload;
  static void clearInitialPayload() => _initialPayload = null;

  static void handleNotificationTap(String payload) {
    AppLogger.debug(
      '[NotificationService] Tap response with payload: $payload',
    );
    selectNotificationNotifier.value = payload;
  }

  // ── Pending queues ────────────────────────────────────────────────────────
  // Notifications that arrived before init completed are queued and flushed
  // once initialization finishes (instead of being silently dropped).
  static final List<({
    int id,
    String title,
    String body,
    NotificationCategory category,
    String? payload,
  })> _pending = [];

  static final List<({
    int id,
    String title,
    String body,
    DateTime scheduledDate,
    NotificationCategory category,
    String? payload,
  })> _pendingScheduled = [];

  // ── Channels & Channel Mapping ─────────────────────────────────────────────

  /// Returns the Android notification channel ID for a given [NotificationCategory].
  static String channelIdFor(NotificationCategory category) {
    return switch (category) {
      NotificationCategory.budget => 'pet_budget_alerts',
      NotificationCategory.anomaly => 'pet_anomalies',
      NotificationCategory.bill => 'pet_bill_reminders',
      NotificationCategory.dailySummary => 'pet_daily_summary',
      NotificationCategory.weeklyReport => 'pet_weekly_insights',
      NotificationCategory.goalProgress => 'pet_goal_progress',
      NotificationCategory.cashflow => 'pet_cashflow_insights',
    };
  }

  /// Returns the configured [AndroidNotificationChannel] for a given [NotificationCategory].
  static AndroidNotificationChannel channelFor(NotificationCategory category) {
    return switch (category) {
      NotificationCategory.budget => const AndroidNotificationChannel(
        'pet_budget_alerts',
        'Budget Alerts',
        description: 'Alerts when approaching or exceeding category budgets',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      NotificationCategory.anomaly => const AndroidNotificationChannel(
        'pet_anomalies',
        'Spending Anomalies',
        description: 'Alerts for unusual or duplicate transactions',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      NotificationCategory.bill => const AndroidNotificationChannel(
        'pet_bill_reminders',
        'Bill Reminders',
        description: 'Upcoming and overdue bill payment reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      NotificationCategory.dailySummary => const AndroidNotificationChannel(
        'pet_daily_summary',
        'Daily Summary',
        description: 'Daily summary of expenses and budget progress',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
      ),
      NotificationCategory.weeklyReport => const AndroidNotificationChannel(
        'pet_weekly_insights',
        'Weekly Insights',
        description: 'Weekly financial insights and report summaries',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
      NotificationCategory.goalProgress => const AndroidNotificationChannel(
        'pet_goal_progress',
        'Goal Progress',
        description: 'Savings milestone updates and target progress',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
      ),
      NotificationCategory.cashflow => const AndroidNotificationChannel(
        'pet_cashflow_insights',
        'Cashflow Insights',
        description: 'Cashflow forecasting and runway alerts',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
      ),
    };
  }

  /// Legacy notification channel kept for backward compatibility with notifications
  /// scheduled or displayed before per-category channels were introduced.
  /// Android notification channels are immutable and permanent once created on a device.
  static const AndroidNotificationChannel _legacyChannel =
      AndroidNotificationChannel(
    'pet_alerts',
    'PET Alerts',
    description: 'Budget, anomaly, and bill alerts',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// All notification channels to register on Android initialization.
  static List<AndroidNotificationChannel> get allChannels => [
        ...NotificationCategory.values.map(channelFor),
        _legacyChannel,
      ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Queries current notification permission status and updates [permissionNotifier].
  static Future<PermissionStatus> permissionStatus() async {
    final status = await Permission.notification.status;
    permissionNotifier.value = status;
    return status;
  }

  /// Explicitly requests notification permission from the user (e.g. via rationale banner or settings).
  ///
  /// On Android 13+ (API 33+), prompts via [Permission.notification.request()].
  /// On iOS, requests alert, badge, and sound permissions via the local notifications plugin.
  /// Updates and returns the new [PermissionStatus].
  static Future<PermissionStatus> requestPermission() async {
    try {
      final status = await Permission.notification.request();

      // For iOS plugin sync:
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      permissionNotifier.value = status;
      return status;
    } catch (e, st) {
      AppLogger.debug('[NotificationService] requestPermission error: $e');
      _recordCrashlyticsError(
        e,
        st,
        reason: 'notification_request_permission_failed',
      );
      return await permissionStatus();
    }
  }

  /// Must be called once during app startup (in `main()`).
  /// Sets up channels and notification infrastructure WITHOUT unconditionally requesting
  /// notification permissions on boot.
  static Future<void> initialize() async {
    if (_isInitialized) {
      await permissionStatus();
      return;
    }

    // ── Android settings ────────────────────────────────────────────────────
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // ── iOS / macOS settings ────────────────────────────────────────────────
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // We request manually on user opt-in
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            handleNotificationTap(payload);
          }
        },
      );

      // Check cold start launch payload
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchDetails?.notificationResponse?.payload != null) {
        final payload = launchDetails!.notificationResponse!.payload!;
        if (payload.isNotEmpty) {
          _initialPayload = payload;
        }
      }

      // ── Android: register per-category channels (no permission required to create channels)
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        for (final channel in allChannels) {
          await androidPlugin.createNotificationChannel(channel);
        }
      }
    } catch (e, st) {
      AppLogger.debug(
        '[NotificationService] Plugin initialization error: $e',
      );
      _recordCrashlyticsError(e, st, reason: 'notification_init_failed');
    }

    _isInitialized = true;
    await permissionStatus();

    // Flush any instant notifications that arrived before init completed
    for (final n in _pending) {
      final enabled =
          await NotificationPreferencesService.isCategoryEnabled(n.category);
      if (enabled) {
        await _showInternal(
          id: n.id,
          title: n.title,
          body: n.body,
          category: n.category,
          payload: n.payload,
        );
      }
    }
    _pending.clear();

    // Flush any scheduled notifications that arrived before init completed
    final now = DateTime.now();
    for (final n in _pendingScheduled) {
      final enabled =
          await NotificationPreferencesService.isCategoryEnabled(n.category);
      if (!enabled) continue;

      if (n.scheduledDate.isBefore(now)) {
        AppLogger.debug(
          '[NotificationService] Scheduled notification date passed before init (id=${n.id}) — skipping',
        );
        continue;
      }

      await _scheduleInternal(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: n.scheduledDate,
        category: n.category,
        payload: n.payload,
      );
    }
    _pendingScheduled.clear();
  }

  /// Shows an immediate notification if the category preference is enabled.
  ///
  /// If called before [initialize] completes, the notification is queued and
  /// delivered as soon as the service is ready — it is never silently dropped.
  ///
  /// [id] should be unique per alert; use [collisionSafeId] for a safe value.
  static Future<void> showInstant({
    required int id,
    required String title,
    required String body,
    required NotificationCategory category,
    String? payload,
  }) async {
    final enabled =
        await NotificationPreferencesService.isCategoryEnabled(category);
    if (!enabled) {
      AppLogger.debug(
        '[NotificationService] Notification dropped (category ${category.name} is disabled)',
      );
      return;
    }

    if (!_isInitialized) {
      // Queue instead of silently dropping
      _pending.add((
        id: id,
        title: title,
        body: body,
        category: category,
        payload: payload,
      ));
      return;
    }
    await _showInternal(
      id: id,
      title: title,
      body: body,
      category: category,
      payload: payload,
    );
  }

  /// Schedules a notification at a specific date and time if category is enabled.
  ///
  /// If called before [initialize] completes, the request is queued and
  /// scheduled as soon as initialization completes — it is never silently dropped.
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required NotificationCategory category,
    String? payload,
  }) async {
    final enabled =
        await NotificationPreferencesService.isCategoryEnabled(category);
    if (!enabled) {
      AppLogger.debug(
        '[NotificationService] Scheduled notification dropped (category ${category.name} is disabled)',
      );
      return;
    }

    if (!_isInitialized) {
      _pendingScheduled.add((
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        category: category,
        payload: payload,
      ));
      return;
    }

    await _scheduleInternal(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      category: category,
      payload: payload,
    );
  }

  /// Derives a collision-safe 32-bit int ID from an arbitrary [String] key
  /// (e.g. alert UUID or alertKey). Two different strings will virtually never
  /// produce the same ID — unlike the old timestamp ÷ 1000 approach.
  static int collisionSafeId(String key) {
    // djb2-style hash → fold to 31-bit positive int
    var hash = 5381;
    for (final c in key.codeUnits) {
      hash = ((hash << 5) + hash) + c;
      hash &= 0x7FFFFFFF; // keep positive and within 32-bit range
    }
    return hash;
  }

  /// Returns whether [category] represents a high-importance alert type
  /// (`budget`, `anomaly`, `bill`) that belongs to the [alertsGroupKey] group.
  static bool isAlertCategory(NotificationCategory category) {
    return category == NotificationCategory.budget ||
        category == NotificationCategory.anomaly ||
        category == NotificationCategory.bill;
  }

  /// Posts or updates the Android group summary notification for a batch of alerts.
  static Future<void> postAlertsSummary({
    required List<({String title, String body, NotificationCategory category})>
        alerts,
  }) async {
    if (alerts.isEmpty) return;
    await _postGroupSummaryNotification(alerts: alerts);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  static AndroidNotificationDetails _androidDetailsFor(
    NotificationCategory category, {
    bool setAsGroupSummary = false,
    StyleInformation? styleInformation,
    String? groupKey,
  }) {
    final channel = channelFor(category);
    final priority = switch (channel.importance) {
      Importance.high || Importance.max => Priority.high,
      Importance.low || Importance.min => Priority.low,
      _ => Priority.defaultPriority,
    };

    final effectiveGroupKey =
        groupKey ?? (isAlertCategory(category) ? alertsGroupKey : null);

    return AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: priority,
      playSound: channel.playSound,
      enableVibration: channel.enableVibration,
      visibility: NotificationVisibility.private,
      groupKey: effectiveGroupKey,
      setAsGroupSummary: setAsGroupSummary,
      styleInformation: styleInformation,
    );
  }

  static Future<void> _showInternal({
    required int id,
    required String title,
    required String body,
    required NotificationCategory category,
    String? payload,
  }) async {
    try {
      final details = NotificationDetails(
        android: _androidDetailsFor(category),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(id, title, body, details, payload: payload);

      if (isAlertCategory(category)) {
        await _trackAlertAndMaybePostSummary(
          title: title,
          body: body,
          category: category,
        );
      }
    } catch (e, st) {
      AppLogger.debug('[NotificationService] show failed (id=$id): $e');
      _recordCrashlyticsError(
        e,
        st,
        reason: 'notification_show_failed (id=$id)',
      );
    }
  }

  static Future<void> _trackAlertAndMaybePostSummary({
    required String title,
    required String body,
    required NotificationCategory category,
  }) async {
    final now = DateTime.now();
    _recentAlertHistory.removeWhere(
      (item) => now.difference(item.timestamp) > groupSummaryRollingWindow,
    );
    _recentAlertHistory.add((
      timestamp: now,
      title: title,
      body: body,
      category: category,
    ));

    if (_recentAlertHistory.length > groupSummaryThreshold) {
      await _postGroupSummaryNotification(
        alerts: _recentAlertHistory
            .map((a) => (title: a.title, body: a.body, category: a.category))
            .toList(),
      );
    }
  }

  static Future<void> _postGroupSummaryNotification({
    required List<({String title, String body, NotificationCategory category})>
        alerts,
  }) async {
    try {
      final count = alerts.length;
      final summaryTitle = '$count new alerts';
      final lines = alerts.map((a) => '${a.title}: ${a.body}').toList();
      final summaryBody = alerts.map((a) => a.title).toSet().join(', ');

      final inboxStyle = InboxStyleInformation(
        lines,
        contentTitle: summaryTitle,
        summaryText: 'PET Alerts',
      );

      final details = NotificationDetails(
        android: _androidDetailsFor(
          NotificationCategory.budget,
          setAsGroupSummary: true,
          groupKey: alertsGroupKey,
          styleInformation: inboxStyle,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.show(
        alertsSummaryNotificationId,
        summaryTitle,
        summaryBody,
        details,
        payload: 'summary:alerts',
      );
    } catch (e, st) {
      AppLogger.debug('[NotificationService] summary notification failed: $e');
      _recordCrashlyticsError(
        e,
        st,
        reason: 'notification_summary_failed',
      );
    }
  }

  static Future<void> _scheduleInternal({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required NotificationCategory category,
    String? payload,
  }) async {
    try {
      final details = NotificationDetails(
        android: _androidDetailsFor(category),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e, st) {
      AppLogger.debug('[NotificationService] schedule failed (id=$id): $e');
      _recordCrashlyticsError(
        e,
        st,
        reason: 'notification_schedule_failed (id=$id)',
      );
    }
  }

  static void _recordCrashlyticsError(
    Object exception,
    StackTrace stackTrace, {
    required String reason,
  }) {
    try {
      FirebaseCrashlytics.instance.recordError(
        exception,
        stackTrace,
        reason: reason,
        fatal: false,
      );
    } catch (_) {
      // Safe fallback when Firebase or Crashlytics is not initialized (e.g. unit tests)
    }
  }
}
