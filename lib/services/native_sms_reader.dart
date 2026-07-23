import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;

import 'package:flutter/services.dart';

/// Data class representing a raw SMS message from the native reader.
class NativeSmsMessage {
  final String address;
  final String body;
  final int dateMillis;
  final int type; // 1=inbox, 2=sent, 3=draft

  NativeSmsMessage({
    required this.address,
    required this.body,
    required this.dateMillis,
    this.type = 1,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(dateMillis);

  /// Whether this message is from the inbox (received).
  bool get isInbox => type == 1;

  /// Whether this message is from the sent box.
  bool get isSent => type == 2;

  factory NativeSmsMessage.fromMap(Map<dynamic, dynamic> map) {
    // Prioritize `date` (device receipt time) over `date_sent` (SMSC time).
    // SMSC times are notoriously buggy on some Indian carrier networks and can
    // cause 12-hour timezone offsets (e.g. 10:25 AM instead of 10:25 PM) and
    // hash mismatches between live broadcasts and ContentResolver scans.
    final int dateReceived = (map['date'] as num?)?.toInt() ?? 0;
    final int dateSent = (map['date_sent'] as num?)?.toInt() ?? 0;
    final int finalDateMillis = dateReceived > 0 ? dateReceived : dateSent;

    return NativeSmsMessage(
      address: map['address'] as String? ?? '',
      body: map['body'] as String? ?? '',
      dateMillis: finalDateMillis,
      type: (map['type'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Native SMS reader that uses Android's ContentResolver to read SMS directly
/// from the system content provider (content://sms/inbox).
///
/// This approach works regardless of which app is set as the default SMS
/// application, because the system content provider stores ALL SMS.
class NativeSmsReader {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.pet.tracker/sms_reader',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.pet.tracker/sms_incoming',
  );
  static const EventChannel _notificationEventChannel = EventChannel(
    'com.pet.tracker/notification_incoming',
  );

  static final NativeSmsReader _instance = NativeSmsReader._internal();
  factory NativeSmsReader() => _instance;
  NativeSmsReader._internal();

  Stream<NativeSmsMessage>? _incomingSmsStream;
  Stream<NativeSmsMessage>? _incomingNotificationStream;

  /// Whether the native reader is available (Android only).
  static bool get isSupported => !kIsWeb && platform.isAndroid;

  // ─── Read Inbox ───────────────────────────────────────────────────

  /// Read SMS messages from the system inbox.
  ///
  /// [lookbackDays] — How many days back to scan.
  /// Returns a list of [NativeSmsMessage] sorted by date (newest first).
  ///
  /// This reads from content://sms/inbox using the Android ContentResolver,
  /// which is independent of the default SMS app.
  Future<List<NativeSmsMessage>> getInboxSms({int lookbackDays = 90}) async {
    return _readSms('getInboxSms', lookbackDays: lookbackDays);
  }

  /// Read SMS messages from the sent box.
  ///
  /// Some UPI confirmations and payment receipts appear in the sent box.
  /// [lookbackDays] — How many days back to scan.
  Future<List<NativeSmsMessage>> getSentSms({int lookbackDays = 90}) async {
    return _readSms('getSentSms', lookbackDays: lookbackDays);
  }

  /// Read ALL SMS messages (inbox + sent) from the system.
  ///
  /// Useful for comprehensive first-time scanning.
  /// [lookbackDays] — How many days back to scan.
  Future<List<NativeSmsMessage>> getAllSms({int lookbackDays = 90}) async {
    return _readSms('getAllSms', lookbackDays: lookbackDays);
  }

  /// Internal method to read SMS via MethodChannel.
  Future<List<NativeSmsMessage>> _readSms(
    String method, {
    int lookbackDays = 90,
  }) async {
    if (!isSupported) {
      AppLogger.debug('[NativeSmsReader] Not supported on this platform');
      return [];
    }

    try {
      // Clamp to a reasonable range. Duration.inMilliseconds is 64-bit
      // in Dart but Flutter's method codec may send small values as
      // 32-bit int to the platform channel.
      final clampedDays = lookbackDays.clamp(1, 365);
      final lookbackMillis = Duration(days: clampedDays).inMilliseconds;

      AppLogger.debug(
        '[NativeSmsReader] Calling $method with lookbackDays=$clampedDays',
      );

      final List<dynamic>? result = await _methodChannel.invokeMethod(method, {
        'lookbackMillis': lookbackMillis,
      });

      if (result == null) {
        AppLogger.debug('[NativeSmsReader] $method returned null');
        return [];
      }

      AppLogger.debug(
        '[NativeSmsReader] $method returned ${result.length} messages',
      );

      return result
          .map(
            (item) => NativeSmsMessage.fromMap(item as Map<dynamic, dynamic>),
          )
          .toList();
    } on PlatformException catch (e) {
      AppLogger.debug(
        '[NativeSmsReader] Platform error reading SMS ($method): ${e.message}',
      );
      return [];
    } catch (e) {
      AppLogger.debug('[NativeSmsReader] Error reading SMS ($method): $e');
      return [];
    }
  }

  // ─── Live Listener ────────────────────────────────────────────────

  /// Get a stream of incoming SMS messages.
  ///
  /// Uses an EventChannel backed by a BroadcastReceiver for
  /// android.provider.Telephony.SMS_RECEIVED — this broadcast goes to
  /// ALL apps with RECEIVE_SMS permission, not just the default SMS app.
  Stream<NativeSmsMessage> get incomingSmsStream {
    _incomingSmsStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => NativeSmsMessage.fromMap(event as Map<dynamic, dynamic>),
    );
    return _incomingSmsStream!;
  }

  /// Get a stream of incoming UPI app notification messages.
  ///
  /// Uses an EventChannel backed by TransactionNotificationListener,
  /// which captures push notifications from Google Pay, PhonePe, Paytm,
  /// and other whitelisted financial apps.
  Stream<NativeSmsMessage> get incomingNotificationStream {
    _incomingNotificationStream ??= _notificationEventChannel
        .receiveBroadcastStream()
        .map(
          (event) => NativeSmsMessage.fromMap(event as Map<dynamic, dynamic>),
        );
    return _incomingNotificationStream!;
  }

  /// Check if notification listener access is granted.
  Future<bool> hasNotificationAccess() async {
    if (!isSupported) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'hasNotificationAccess',
      );
      return result ?? false;
    } catch (e) {
      AppLogger.debug(
        '[NativeSmsReader] Error checking notification access: $e',
      );
      return false;
    }
  }

  /// Request notification listener access (opens system settings).
  Future<void> requestNotificationAccess() async {
    if (!isSupported) return;
    try {
      await _methodChannel.invokeMethod('requestNotificationAccess');
    } catch (e) {
      AppLogger.debug(
        '[NativeSmsReader] Error requesting notification access: $e',
      );
    }
  }

  /// Explicitly start the native SMS listener.
  Future<void> startListening() async {
    if (!isSupported) return;
    try {
      await _methodChannel.invokeMethod('startListening');
    } catch (e) {
      AppLogger.debug('[NativeSmsReader] Error starting listener: $e');
    }
  }

  /// Stop the native SMS listener.
  Future<void> stopListening() async {
    if (!isSupported) return;
    try {
      await _methodChannel.invokeMethod('stopListening');
    } catch (e) {
      AppLogger.debug('[NativeSmsReader] Error stopping listener: $e');
    }
  }

  // ─── Reconciliation Query ────────────────────────────────────────

  /// Read SMS since an absolute timestamp (epoch millis) for reconciliation.
  ///
  /// Uses a dedicated native method that validates the watermark and
  /// falls back to [fallbackDays]-day lookback if the timestamp is
  /// missing, corrupted, or in the future.
  ///
  /// Results are sorted oldest-first (ASC) to allow sequential
  /// watermark advancement.
  ///
  /// [sinceTimestamp] — Epoch milliseconds. Null triggers fallback.
  /// [fallbackDays]   — Days to look back when timestamp is unusable.
  Future<List<NativeSmsMessage>> getSmsSinceTimestamp({
    int? sinceTimestamp,
    int fallbackDays = 7,
  }) async {
    if (!isSupported) return [];

    try {
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getSmsSince',
        {
          'sinceTimestamp': sinceTimestamp,
          'fallbackDays': fallbackDays.clamp(1, 365),
        },
      );

      if (result == null) return [];

      return result
          .map(
            (item) => NativeSmsMessage.fromMap(item as Map<dynamic, dynamic>),
          )
          .toList();
    } on PlatformException catch (e) {
      AppLogger.debug(
        '[NativeSmsReader] Platform error in getSmsSinceTimestamp: ${e.message}',
      );
      return [];
    } catch (e) {
      AppLogger.debug('[NativeSmsReader] Error in getSmsSinceTimestamp: $e');
      return [];
    }
  }

  // ─── OEM & Battery Optimization Utilities ───────────────────────

  static const List<String> aggressiveOems = [
    'xiaomi',
    'redmi',
    'poco',
    'oppo',
    'vivo',
    'realme',
  ];

  /// Get device manufacturer name (e.g., "Xiaomi", "OPPO", "Vivo", "Realme").
  Future<String> getDeviceManufacturer() async {
    if (!isSupported) return 'unknown';
    try {
      final String manufacturer =
          await _methodChannel.invokeMethod('getDeviceManufacturer');
      return manufacturer;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Check if the current device is from an OEM known for aggressive process killing.
  Future<bool> isAggressiveOem() async {
    final manufacturer = (await getDeviceManufacturer()).toLowerCase();
    return aggressiveOems.any((oem) => manufacturer.contains(oem));
  }

  /// Open battery optimization settings to allow user to whitelist P.E.T.
  Future<bool> openBatteryOptimizationSettings() async {
    if (!isSupported) return false;
    try {
      final bool success =
          await _methodChannel.invokeMethod('openBatteryOptimizationSettings');
      return success;
    } catch (_) {
      return false;
    }
  }
}
