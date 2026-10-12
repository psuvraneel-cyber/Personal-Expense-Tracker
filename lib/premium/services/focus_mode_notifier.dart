import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:intl/intl.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/category_repository.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/models/spend_pause.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/premium/services/spend_pause_service.dart';

/// Focus Mode for payments the app imports (SMS / payment notifications).
///
/// The app can't stop or warn before a payment made in another app, so when
/// an imported payment lands in a paused category the user gets a
/// notification instead. Manual entries are warned before saving
/// (AddEditTransactionScreen).
class FocusModeNotifier {
  FocusModeNotifier._();

  static final _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  /// The notification text, or null when [txn] isn't in a paused category.
  @visibleForTesting
  static String? messageFor(
    TransactionRecord txn,
    SpendPause pause, {
    required String categoryName,
  }) {
    if (txn.type != TransactionType.expense) return null;
    if (!pause.isCategoryBlocked(txn.categoryId)) return null;
    final where = (txn.merchantName?.trim().isNotEmpty ?? false)
        ? ' at ${txn.merchantName!.trim()}'
        : '';
    return '${_inr.format(txn.amount)}$where was recorded in $categoryName, '
        'which you paused.';
  }

  static Future<void> notifyIfPaused(
    TransactionRecord txn, {
    String? userId,
  }) async {
    if (kIsWeb || txn.type != TransactionType.expense) return;
    try {
      final pause = await SpendPauseService.getState(userId: userId);
      if (!pause.isCategoryBlocked(txn.categoryId)) return;
      final category =
          await CategoryRepository().getCategoryById(txn.categoryId);
      final body = messageFor(txn, pause,
          categoryName: category?.name ?? 'a paused category');
      if (body == null) return;
      await NotificationService.showInstant(
        id: NotificationService.collisionSafeId('focus:${txn.id}'),
        title: 'Focus Mode',
        body: body,
        category: NotificationCategory.budget,
        payload: 'focus',
      );
    } catch (e) {
      AppLogger.debug('[FocusModeNotifier] failed: $e');
    }
  }
}
