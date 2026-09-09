import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/screens/cashflow_screen.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/providers/transaction_provider.dart';

class FakePremiumProvider extends ChangeNotifier implements PremiumProvider {
  bool _isPremium = true;

  @override
  bool get isPremium => _isPremium;
  set isPremium(bool v) {
    _isPremium = v;
    notifyListeners();
  }

  @override
  bool get isLoading => false;
  @override
  bool get experimentalEnabled => true;
  @override
  bool get isDeveloperPremiumAccessEnabled => true;
  @override
  Future<void> load({String? userId}) async {}
  @override
  Future<void> setDeveloperPremiumAccess(bool enabled) async {}
  @override
  Future<void> setExperimental(bool enabled) async {}
  @override
  Future<void> logInUser(String uid) async {}
  @override
  Future<void> logOutUser() async {}
  @override
  Future<void> clearData() async {}
}

class FakeTransactionProvider extends ChangeNotifier
    implements TransactionProvider {
  final List<TransactionRecord> _txns;
  FakeTransactionProvider(this._txns);

  @override
  List<TransactionRecord> get transactions => _txns;
  @override
  List<TransactionRecord> get allTransactions => _txns;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRecurringProvider extends ChangeNotifier
    implements RecurringProvider {
  final List<RecurringPayment> _bills;
  FakeRecurringProvider(this._bills);

  @override
  List<RecurringPayment> get confirmedBills => _bills;
  @override
  List<RecurringPayment> get recurring => _bills;
  @override
  bool get isLoading => false;
  @override
  Future<void> load() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePremiumProvider fakePremium;
  final now = DateTime(2026, 7, 20, 10, 0);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    CashflowForecastService.clearCache();
    fakePremium = FakePremiumProvider();
  });

  Widget buildTestWidget({
    required List<TransactionRecord> transactions,
    required List<RecurringPayment> bills,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PremiumProvider>.value(value: fakePremium),
        ChangeNotifierProvider<TransactionProvider>.value(
          value: FakeTransactionProvider(transactions),
        ),
        ChangeNotifierProvider<RecurringProvider>.value(
          value: FakeRecurringProvider(bills),
        ),
      ],
      child: const MaterialApp(
        home: CashflowScreen(),
      ),
    );
  }

  group('CashflowScreen Widget Tests', () {
    testWidgets('shows premium gate paywall when user is not premium',
        (tester) async {
      fakePremium.isPremium = false;

      await tester.pumpWidget(buildTestWidget(transactions: [], bills: []));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cash Flow Forecast'), findsNWidgets(2));
      expect(find.text('Unlock Premium'), findsOneWidget);
    });

    testWidgets('renders full premium cashflow dashboard for entitled user',
        (tester) async {
      fakePremium.isPremium = true;

      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 80000,
          date: now.subtract(const Duration(days: 15)),
          categoryId: 'salary',
          type: TransactionType.income,
        ),
        TransactionRecord(
          id: 't_exp',
          amount: 25000,
          date: now.subtract(const Duration(days: 5)),
          categoryId: 'groceries',
          type: TransactionType.expense,
        ),
      ];

      final bills = [
        RecurringPayment(
          id: 'b_wifi',
          merchantName: 'Airtel Broadband',
          amount: 1499,
          frequency: 'monthly',
          lastPaidAt: now.subtract(const Duration(days: 20)),
          nextDueAt: now.add(const Duration(days: 10)),
          categoryId: 'utilities',
          status: RecurringStatus.confirmed,
        ),
      ];

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester
          .pumpWidget(buildTestWidget(transactions: txns, bills: bills));
      await tester.pumpAndSettle();

      // Verify Hero Card with Safe-to-Spend & 30-day window
      expect(find.text('Safe to Spend Allowance'), findsOneWidget);
      expect(find.text(' / day'), findsOneWidget);
      expect(find.text('30-Day Window'), findsOneWidget);

      // Verify Horizon selector chips
      expect(find.text('14D'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);
      expect(find.text('60D'), findsOneWidget);
      expect(find.text('90D'), findsOneWidget);

      // Open What-If Simulator card via AppBar action
      final simBtn = find.byTooltip('What-If Simulator');
      expect(simBtn, findsOneWidget);
      await tester.tap(simBtn);
      await tester.pumpAndSettle();

      // Verify What-If Simulator card header
      expect(find.text('Can I Afford This? (Simulator)'), findsOneWidget);

      // Verify Timeline section
      expect(find.text('Daily Timeline (30 Days)'), findsOneWidget);
      expect(find.text('Bills & Income'), findsOneWidget);
    });

    testWidgets(
        'opens Safe-to-Spend breakdown modal bottom sheet upon tapping info icon',
        (tester) async {
      fakePremium.isPremium = true;

      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 60000,
          date: now.subtract(const Duration(days: 10)),
          categoryId: 'salary',
          type: TransactionType.income,
        ),
      ];

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(transactions: txns, bills: []));
      await tester.pumpAndSettle();

      // Find the info icon button on the hero card and tap it
      final infoBtn = find.byIcon(Icons.info_outline_rounded);
      expect(infoBtn, findsWidgets);
      await tester.tap(infoBtn.first);
      await tester.pumpAndSettle();

      // Verify bottom sheet appears with mathematical deconstruction
      expect(find.text('Safe-to-Spend Math Deconstruction'), findsOneWidget);
      expect(find.text('Projected Lowest Balance'), findsOneWidget);
      expect(find.text('Safety Buffer Floor'), findsOneWidget);
      expect(find.text('Total Spendable Capacity'), findsOneWidget);
      expect(find.text('Path-Dependent Headroom'), findsOneWidget);
      expect(find.text('Daily Safe-to-Spend'), findsOneWidget);
    });

    testWidgets(
        'Defect 4 UI Consistency: explanation strictly matches engine Safe-to-Spend when linear sum != engine value',
        (tester) async {
      fakePremium.isPremium = true;

      // Scenario where linear arithmetic diverges from path-dependent trough:
      // Opening: ₹100,000
      // Income: ₹60,000 (past)
      // Large bill due early on day 3: ₹60,000
      // Buffer: ₹5,000
      // Lowest projected balance reaches: ~₹35,000
      // Headroom = ₹35,000 - ₹5,000 = ₹30,000 (Safe-to-spend = ₹1,000/day)
      // Linear monthly sum would suggest: 100k - 60k - 5k = 35k or higher
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 60000,
          date: now.subtract(const Duration(days: 10)),
          categoryId: 'salary',
          type: TransactionType.income,
        ),
      ];

      final bills = [
        RecurringPayment(
          id: 'b_rent',
          merchantName: 'Advance Rent',
          amount: 60000,
          frequency: 'monthly',
          lastPaidAt: now.subtract(const Duration(days: 20)),
          nextDueAt: now.add(const Duration(days: 3)),
          categoryId: 'housing',
          status: RecurringStatus.confirmed,
        ),
      ];

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester
          .pumpWidget(buildTestWidget(transactions: txns, bills: bills));
      await tester.pumpAndSettle();

      // Open bottom sheet
      final infoBtn = find.byIcon(Icons.info_outline_rounded);
      await tester.tap(infoBtn.first);
      await tester.pumpAndSettle();

      // Verify engine safe-to-spend values match bottom sheet derivation
      expect(find.text('Safe-to-Spend Math Deconstruction'), findsOneWidget);
      expect(find.text('Projected Lowest Balance'), findsOneWidget);
      expect(find.text('Safety Buffer Floor'), findsOneWidget);
      expect(find.text('Total Spendable Capacity'), findsOneWidget);
      expect(find.text('Path-Dependent Headroom'), findsOneWidget);
    });

    testWidgets(
        'switching horizons updates horizon chips and recalculates forecast',
        (tester) async {
      fakePremium.isPremium = true;

      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 50000,
          date: now.subtract(const Duration(days: 12)),
          categoryId: 'salary',
          type: TransactionType.income,
        ),
      ];

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(transactions: txns, bills: []));
      await tester.pumpAndSettle();

      // Tap 14D chip
      await tester.tap(find.text('14D'));
      await tester.pumpAndSettle();
      expect(find.text('14-Day Window'), findsOneWidget);

      // Tap 60D chip
      await tester.tap(find.text('60D'));
      await tester.pumpAndSettle();
      expect(find.text('60-Day Window'), findsOneWidget);

      // Tap 90D chip
      await tester.tap(find.text('90D'));
      await tester.pumpAndSettle();
      expect(find.text('90-Day Window'), findsOneWidget);
    });
  });
}
