import 'package:pet/core/utils/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/theme_mode_notifier.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/firebase_options.dart';
import 'package:pet/screens/splash/splash_screen.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/providers/linked_account_provider.dart';
import 'package:pet/premium/providers/family_provider.dart';
import 'package:pet/premium/providers/tax_provider.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/services/firebase_auth_service.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/providers/dashboard_config_provider.dart';
import 'package:pet/services/haptic_service.dart';
import 'package:pet/services/biometric_service.dart';
import 'package:pet/screens/biometric/biometric_lock_screen.dart';

import 'package:timezone/data/latest.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  // Prevent Google Fonts from downloading at runtime — use bundled fonts only
  GoogleFonts.config.allowRuntimeFetching = false;

  // Theme mode is loaded from SharedPreferences below

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    AppLogger.debug('Firebase init failed: $e');
  }

  // Silently restore Google + Firebase session on cold start (Android/iOS).
  // Must run after Firebase.initializeApp() and before runApp().
  try {
    await FirebaseAuthService().tryRestoreSession();
  } catch (e) {
    AppLogger.debug('Silent session restore failed: $e');
  }

  // Initialize haptic feedback preference
  await HapticService.instance.init();

  // Initialize biometric lock preference
  await BiometricService.instance.init();

  try {
    // Initialize database
    await DatabaseHelper().database;
    // Verify database integrity on startup
    final isHealthy = await DatabaseHelper().runIntegrityCheck();
    if (!isHealthy) {
      AppLogger.debug(
        '[MAIN] ⚠️ Database corruption detected — cloud data preserved in Firestore',
      );
    }
  } catch (e) {
    AppLogger.debug('Database init failed: $e');
  }

  try {
    // Initialize notifications
    await NotificationService.initialize();
  } catch (e) {
    AppLogger.debug('Notification init failed: $e');
  }

  ThemeMode themeMode = ThemeMode.system;
  try {
    // Load preferences
    final prefs = await SharedPreferences.getInstance();
    final themePref = prefs.getString('themeMode') ?? 'system';
    themeMode = switch (themePref) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

    final deletionInProgress = prefs.getBool('deletion_in_progress') ?? false;
    if (deletionInProgress) {
      AccountDeletionService.isDeletionInProgress = true;
    }
  } catch (e, stack) {
    AppLogger.debug('SharedPreferences failed: $e');
    AppLogger.debug('SharedPreferences stack: $stack');
  }

  runApp(PETApp(themeMode: themeMode));
}

class PETApp extends StatefulWidget {
  final ThemeMode themeMode;

  const PETApp({super.key, required this.themeMode});

  @override
  State<PETApp> createState() => _PETAppState();
}

class _PETAppState extends State<PETApp> with WidgetsBindingObserver {
  /// ValueNotifier so only the [ValueListenableBuilder] wrapping [MaterialApp]
  /// rebuilds on theme toggle — providers and their descendants remain mounted.
  late final ValueNotifier<ThemeMode> _themeMode;

  /// Key to access navigator context (and thus providers) from auth listener.
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// Tracks the previously seen UID so we only reload on actual user changes.
  String? _lastUid;

  StreamSubscription<User?>? _authSubscription;

  /// Whether the biometric lock screen is currently showing.
  bool _showBiometricLock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeMode = ValueNotifier<ThemeMode>(widget.themeMode);
    _lastUid = FirebaseAuthService().currentUserId;

    // Centralized auth-state listener — drives data reload / clear.
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthStateChanged,
    );

    // Show biometric lock on cold start if enabled
    if (BiometricService.instance.isEnabled) {
      _showBiometricLock = true;
    } else {
      // Mark active if biometric is not enabled
      BiometricService.instance.markActive();
    }
  }

  void _onAuthStateChanged(User? user) {
    if (AccountDeletionService.isDeletionInProgress) {
      AppLogger.debug('[MAIN] Account deletion in progress — ignoring auth change');
      return;
    }
    final currentUserId = FirebaseAuthService().currentUserId;
    AppLogger.debug(
      '[MAIN] _onAuthStateChanged → uid=$currentUserId '
      '_lastUid=$_lastUid',
    );
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      AppLogger.debug('[MAIN] context null, skipping');
      return;
    }

    if (currentUserId == null && _lastUid != null) {
      AppLogger.debug('[MAIN] Real sign-out detected — clearing data');
      ctx.read<TransactionProvider>().clearData();
      ctx.read<CategoryProvider>().clearData();
      ctx.read<BudgetProvider>().clearData();
      ctx.read<SmsTransactionProvider>().clearData();
      ctx.read<PremiumProvider>().clearData();
      ctx.read<GoalProvider>().clearData();
      ctx.read<AlertProvider>().clearData();
      ctx.read<LinkedAccountProvider>().clearData();
      ctx.read<FamilyProvider>().clearData();
      ctx.read<TaxProvider>().clearData();
      ctx.read<WeeklyPlannerProvider>().clearData();
      ctx.read<DashboardConfigProvider>().clearData();
      _lastUid = null;
    } else if (currentUserId != null && currentUserId != _lastUid) {
      AppLogger.debug(
        '[MAIN] New user signed in ($currentUserId) — reloading data',
      );
      _lastUid = currentUserId;
      ctx.read<CategoryProvider>().loadCategories();
      ctx.read<TransactionProvider>().loadTransactions();
      ctx.read<BudgetProvider>().loadBudgets();
    } else {
      AppLogger.debug('[MAIN] No action taken (same user or null→null)');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _themeMode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AccountDeletionService.isDeletionInProgress) {
      AppLogger.debug('[MAIN] Account deletion in progress — ignoring lifecycle resume');
      return;
    }
    if (state == AppLifecycleState.resumed) {
      try {
        _navigatorKey.currentContext?.read<TransactionProvider>().triggerSyncQueue();
      } catch (e) {
        AppLogger.debug('[MAIN] Failed to trigger sync queue on resume: $e');
      }
      try {
        _navigatorKey.currentContext?.read<SmsTransactionProvider>().runReconciliation();
      } catch (e) {
        AppLogger.debug('[MAIN] Failed to trigger SMS reconciliation on resume: $e');
      }
    }

    if (!BiometricService.instance.isEnabled) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Record the time the app was backgrounded
      BiometricService.instance.markActive();
    } else if (state == AppLifecycleState.resumed) {
      // Check if the idle timeout has elapsed
      if (BiometricService.instance.isLocked && !_showBiometricLock) {
        setState(() => _showBiometricLock = true);
      }
    }
  }

  void _onBiometricUnlocked() {
    BiometricService.instance.markActive();
    setState(() => _showBiometricLock = false);
  }

  void _setThemeMode(ThemeMode mode) async {
    _themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    final key = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await prefs.setString('themeMode', key);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CategoryProvider()..loadCategories(),
        ),
        ChangeNotifierProvider(
          create: (_) => TransactionProvider()..loadTransactions(),
        ),
        ChangeNotifierProxyProvider<TransactionProvider, BudgetProvider>(
          create: (_) => BudgetProvider()..loadBudgets(),
          update: (_, txnProvider, budgetProvider) {
            budgetProvider?.refreshSpentFromTransactions(
              txnProvider.allTransactions,
            );
            return budgetProvider ?? BudgetProvider();
          },
        ),
        ChangeNotifierProvider(
          create: (_) => SmsTransactionProvider()..initialize(),
        ),
        ChangeNotifierProvider(create: (_) => PremiumProvider()..load()),
        ChangeNotifierProxyProvider<SmsTransactionProvider, RecurringProvider>(
          create: (_) => RecurringProvider()..load(),
          update: (_, smsProvider, recurringProvider) {
            if (smsProvider.transactions.isNotEmpty) {
              recurringProvider?.refreshFromSms(smsProvider.transactions);
            }
            return recurringProvider ?? RecurringProvider();
          },
        ),
        ChangeNotifierProvider(create: (_) => GoalProvider()..load()),
        ChangeNotifierProxyProvider2<
          TransactionProvider,
          BudgetProvider,
          AlertProvider
        >(
          create: (_) => AlertProvider()..load(),
          update: (_, txnProvider, budgetProvider, alertProvider) {
            if (txnProvider.allTransactions.isNotEmpty) {
              alertProvider?.refreshAnomalies(txnProvider.allTransactions);
            }
            if (budgetProvider.budgets.isNotEmpty) {
              final budgets = {
                for (final b in budgetProvider.budgets) b.categoryId: b.amount,
              };
              alertProvider?.refreshBudgetAlerts(
                budgets: budgets,
                spent: budgetProvider.spentAmounts,
              );
            }
            return alertProvider ?? AlertProvider();
          },
        ),
        ChangeNotifierProvider(create: (_) => LinkedAccountProvider()..load()),
        ChangeNotifierProvider(create: (_) => FamilyProvider()..load()),
        ChangeNotifierProvider(
          create: (_) => DashboardConfigProvider()..load(),
        ),
        ChangeNotifierProvider(create: (_) => TaxProvider()),
        Provider(
          create: (_) => AccountDeletionService(dbHelper: DatabaseHelper()),
        ),
        ChangeNotifierProxyProvider<TransactionProvider, WeeklyPlannerProvider>(
          create: (_) => WeeklyPlannerProvider()..load(),
          update: (_, txnProvider, plannerProvider) {
            plannerProvider?.refreshFromTransactions(
              txnProvider.allTransactions,
            );
            return plannerProvider ?? WeeklyPlannerProvider();
          },
        ),
      ],
      // ValueListenableBuilder scopes rebuilds to just MaterialApp —
      // providers and all descendant screens are not recreated on toggle.
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeMode,
        builder: (context, themeMode, _) => ThemeModeNotifier(
          themeMode: themeMode,
          onThemeModeChanged: _setThemeMode,
          child: MaterialApp(
            title: 'P.E.T - Personal Expense Tracker',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            // 200 ms feels instant but still has a subtle crossfade.
            themeAnimationDuration: const Duration(milliseconds: 200),
            themeAnimationCurve: Curves.easeOut,
            navigatorKey: _navigatorKey,
            builder: (context, child) {
              // Biometric lock overlay sits above all navigation
              return Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  if (_showBiometricLock)
                    BiometricLockScreen(onUnlocked: _onBiometricUnlocked),
                ],
              );
            },
            routes: {
              '/': (_) => SplashScreen(
                onThemeToggle: () => _setThemeMode(
                  themeMode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
                onThemeModeChanged: _setThemeMode,
                themeMode: themeMode,
                isDarkMode:
                    themeMode == ThemeMode.dark ||
                    (themeMode == ThemeMode.system &&
                        WidgetsBinding
                                .instance
                                .platformDispatcher
                                .platformBrightness ==
                            Brightness.dark),
              ),
            },
            initialRoute: '/',
          ),
        ),
      ),
    );
  }
}
