import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/providers/family_provider.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/providers/linked_account_provider.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/providers/spend_pause_provider.dart';
import 'package:pet/premium/providers/tax_provider.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/dashboard_config_provider.dart';
import 'package:pet/providers/recurring_transaction_provider.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/providers/transaction_provider.dart';

/// Clears every provider's in-memory data so nothing from the previous
/// account stays on screen or gets written back.
///
/// Sign-out, account deletion and the sign-out branch of the auth listener
/// all use this, so none of them can forget a provider. It does not touch
/// storage; [LocalDataWiper.wipe] does that.
Future<void> clearAllProviders(BuildContext context) async {
  // Read everything before the first await: the context may be unmounted
  // once navigation starts.
  final invoices = context.read<InvoiceProvider>();
  final transactions = context.read<TransactionProvider>();
  final categories = context.read<CategoryProvider>();
  final budgets = context.read<BudgetProvider>();
  final premium = context.read<PremiumProvider>();
  final recurring = context.read<RecurringProvider>();
  final goals = context.read<GoalProvider>();
  final alerts = context.read<AlertProvider>();
  final recurringTransactions = context.read<RecurringTransactionProvider>();
  final weeklyPlanner = context.read<WeeklyPlannerProvider>();
  final spendPause = context.read<SpendPauseProvider>();
  final sms = context.read<SmsTransactionProvider>();
  final linkedAccounts = context.read<LinkedAccountProvider>();
  final family = context.read<FamilyProvider>();
  final tax = context.read<TaxProvider>();
  final dashboard = context.read<DashboardConfigProvider>();

  await Future.wait([
    invoices.clearData(),
    transactions.clearData(),
    categories.clearData(),
    budgets.clearData(),
    premium.clearData(),
    recurring.clearData(),
    goals.clearData(),
    alerts.clearData(),
    recurringTransactions.clearData(),
    weeklyPlanner.clearData(),
    spendPause.clearData(),
  ]);
  sms.clearData();
  linkedAccounts.clearData();
  family.clearData();
  tax.clearData();
  dashboard.clearData();
}

/// Records which account the data on this device belongs to.
///
/// The wipe clears this key along with the other user preferences, so after
/// a successful sign-out nobody owns the data. If a wipe failed, or rows were
/// added while signed out, the stored owner differs from the account signing
/// in, and the caller wipes again before loading anything.
class DataOwner {
  DataOwner._();

  static const String prefKey = 'pet.dataOwnerUid';

  /// Whether local data may be shown to [uid]. Claims unowned data for [uid].
  static Future<bool> isOwnedBy(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(prefKey);
    if (owner == null) {
      await prefs.setString(prefKey, uid);
      return true;
    }
    return owner == uid;
  }

  /// Marks the (freshly wiped) local data as belonging to [uid].
  static Future<void> claim(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, uid);
  }
}
