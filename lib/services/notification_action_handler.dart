import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/app_bootstrap.dart';
import 'package:pet/services/financial_ingestion_service.dart';

/// Notification payload prefixes for detected transactions.
///  - `obs:<observationId>` — awaiting review (Confirm / Edit / Ignore)
///  - `txn:<observationId>` — auto-imported into the ledger (Edit / Ignore)
const String kReviewPayloadPrefix = 'obs:';
const String kImportedPayloadPrefix = 'txn:';

/// Handles the non-UI action buttons on transaction notifications.
/// Returns `true` if the action was consumed.
Future<bool> handleTransactionNotificationAction(
  String? actionId,
  String? payload,
) async {
  if (actionId == null || payload == null) return false;
  final String observationId;
  if (payload.startsWith(kReviewPayloadPrefix)) {
    observationId = payload.substring(kReviewPayloadPrefix.length);
  } else if (payload.startsWith(kImportedPayloadPrefix)) {
    observationId = payload.substring(kImportedPayloadPrefix.length);
  } else {
    return false;
  }

  final service = FinancialIngestionService();
  switch (actionId) {
    case 'confirm':
      await service.confirmObservation(observationId: observationId);
      return true;
    case 'ignore':
      // Removes the ledger row too if it was auto-imported.
      await service.rejectObservation(
        observationId: observationId,
        reason: 'notification_action_ignore',
      );
      return true;
    default:
      return false;
  }
}

/// Entry point used by flutter_local_notifications when an action button
/// without UI is tapped (runs in a background isolate, even if the app is
/// closed). Must be a top-level function.
@pragma('vm:entry-point')
Future<void> notificationActionBackgroundHandler(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await AppBootstrap.initFirebase();
  try {
    await handleTransactionNotificationAction(
      response.actionId,
      response.payload,
    );
  } catch (e) {
    AppLogger.error('Background notification action failed', error: e);
  }
}
