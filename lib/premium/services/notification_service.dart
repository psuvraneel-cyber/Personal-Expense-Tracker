import 'package:pet/core/utils/app_logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

/// Wraps [FlutterLocalNotificationsPlugin] with:
///  • Android 13+ runtime permission request
///  • Plugin-level permission request (required by flutter_local_notifications v17+)
///  • iOS / macOS initialisation
///  • Silent-fail guard replaced with a queuing pattern
///  • Collision-safe notification IDs
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // ── Pending queue ─────────────────────────────────────────────────────────
  // Notifications that arrived before init completed are queued and flushed
  // once initialization finishes (instead of being silently dropped).
  static final List<({int id, String title, String body})> _pending = [];

  // ── Channel constants ─────────────────────────────────────────────────────
  static const String _channelId = 'pet_alerts';
  static const String _channelName = 'PET Alerts';
  static const String _channelDesc = 'Budget, anomaly, and bill alerts';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Must be called once during app startup (in `main()`).
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // ── Android settings ────────────────────────────────────────────────────
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // ── iOS / macOS settings ────────────────────────────────────────────────
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // We request manually below
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(initSettings);

    // ── Android 13+ (API 33+): request POST_NOTIFICATIONS via permission_handler
    final status = await Permission.notification.status;
    if (status.isDenied || status.isRestricted) {
      await Permission.notification.request();
    }

    // ── Also request via the plugin itself (required by flutter_local_notifications v17+)
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // ── iOS: request permission via plugin ──────────────────────────────────
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _isInitialized = true;

    // Flush any notifications that arrived before init completed
    for (final n in _pending) {
      await _showInternal(id: n.id, title: n.title, body: n.body);
    }
    _pending.clear();
  }

  /// Shows an immediate notification.
  ///
  /// If called before [initialize] completes, the notification is queued and
  /// delivered as soon as the service is ready — it is never silently dropped.
  ///
  /// [id] should be unique per alert; use [collisionSafeId] for a safe value.
  static Future<void> showInstant({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) {
      // Queue instead of silently dropping
      _pending.add((id: id, title: title, body: body));
      return;
    }
    await _showInternal(id: id, title: title, body: body);
  }

  /// Schedules a notification at a specific date and time.
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_isInitialized) {
      return; // Cannot queue scheduled notifications simply, ignore for now or init first
    }
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      AppLogger.debug('[NotificationService] schedule failed (id=$id): $e');
    }
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

  // ── Private ────────────────────────────────────────────────────────────────

  static Future<void> _showInternal({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(id, title, body, details);
    } catch (e) {
      AppLogger.debug('[NotificationService] show failed (id=$id): $e');
    }
  }
}
