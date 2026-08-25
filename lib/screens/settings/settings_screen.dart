import 'package:pet/core/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:provider/provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/theme_mode_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/services/auth_service.dart';
import 'package:pet/screens/sms_transactions/sms_permission_screen.dart';
import 'package:pet/screens/sms_transactions/sms_transactions_screen.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/screens/premium_hub_screen.dart';
import 'package:pet/screens/auth/google_sign_in_screen.dart';
import 'package:pet/services/haptic_service.dart';
import 'package:pet/services/biometric_service.dart';
import 'package:pet/services/export_service.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;
import 'package:pet/screens/settings/account_deletion_sheet.dart';
import 'package:pet/screens/settings/notification_settings_screen.dart';
import 'package:pet/core/widgets/oem_battery_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ThemeMode? themeMode;

  const SettingsScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
    this.onThemeModeChanged,
    this.themeMode,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _defaultPaymentMethod = 'UPI';
  String _userName = '';
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultPaymentMethod = prefs.getString('defaultPaymentMethod') ?? 'UPI';
      _userName = AuthService.userName ?? prefs.getString('userName') ?? '';
      _userEmail = AuthService.userEmail ?? prefs.getString('userEmail') ?? '';
    });
  }

  Future<void> _savePaymentMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultPaymentMethod', method);
    setState(() => _defaultPaymentMethod = method);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeModeNotifier = ThemeModeNotifier.of(context);
    final currentThemeMode = themeModeNotifier.themeMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Profile section
          if (_userName.isNotEmpty) ...[
            _buildProfileCard(context, isDark),
            const SizedBox(height: 16),
          ],

          // Appearance
          _buildSectionTitle(context, 'Appearance'),
          const SizedBox(height: 8),
          _buildThemePicker(context, isDark, currentThemeMode),
          const SizedBox(height: 16),

          // Notifications
          _buildSectionTitle(context, 'Notifications'),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.notifications_none_rounded,
            iconColor: AppTheme.accentPurple,
            title: 'Notification Preferences',
            subtitle: 'Manage budget, anomaly, and bill alert categories',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.battery_charging_full_rounded,
            iconColor: AppTheme.incomeGreen,
            title: 'Battery & Autostart Settings',
            subtitle: 'Prevent MIUI/ColorOS/FuntouchOS from stopping SMS alerts',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const OemBatteryDialog(),
              );
            },
          ),
          const SizedBox(height: 16),

          // Premium
          _buildSectionTitle(context, 'Premium'),
          const SizedBox(height: 8),
          Consumer<PremiumProvider>(
            builder: (context, premium, _) {
              return Column(
                children: [
                  _buildSettingTile(
                    context,
                    isDark: isDark,
                    icon: Icons.workspace_premium_rounded,
                    iconColor: AppTheme.accentPurple,
                    title: 'Premium Hub',
                    subtitle: premium.isPremium
                        ? 'Active (Rs 50/mo, Rs 450/yr)'
                        : 'Unlock premium features',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PremiumHubScreen(),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Currency
          _buildSectionTitle(context, 'Currency'),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.currency_rupee,
            iconColor: AppTheme.incomeGreen,
            title: 'Currency',
            subtitle: '₹ Indian Rupee (INR)',
          ),
          const SizedBox(height: 16),

          // Default payment method
          _buildSectionTitle(context, 'Default Payment Method'),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _defaultPaymentMethod,
            onChanged: (value) {
              if (value != null) _savePaymentMethod(value);
            },
            child: Column(
              children:
                  [
                    'UPI',
                    'Credit Card',
                    'Debit Card',
                    'Cash',
                    'Bank Transfer',
                    'Net Banking',
                    'PayPal',
                  ].map((method) {
                    final isSelected = _defaultPaymentMethod == method;
                    IconData icon;
                    switch (method) {
                      case 'UPI':
                        icon = Icons.phone_android;
                        break;
                      case 'Credit Card':
                        icon = Icons.credit_card;
                        break;
                      case 'Debit Card':
                        icon = Icons.credit_card_outlined;
                        break;
                      case 'Bank Transfer':
                        icon = Icons.account_balance;
                        break;
                      case 'Net Banking':
                        icon = Icons.language;
                        break;
                      case 'PayPal':
                        icon = Icons.paypal_outlined;
                        break;
                      case 'Wallet':
                        icon = Icons.account_balance_wallet_outlined;
                        break;
                      default:
                        icon = Icons.payments_outlined;
                    }
                    return _buildSettingTile(
                      context,
                      isDark: isDark,
                      icon: icon,
                      iconColor: isSelected
                          ? AppTheme.accentPurple
                          : AppTheme.textTertiary,
                      title: method,
                      trailing: Radio<String>(
                        value: method,
                        activeColor: AppTheme.accentPurple,
                      ),
                      onTap: () => _savePaymentMethod(method),
                    );
                  }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Custom Categories
          _buildSectionTitle(context, 'Categories'),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.category,
            iconColor: AppTheme.warningYellow,
            title: 'Manage Custom Categories',
            subtitle: 'Add or remove your categories',
            onTap: () => _showCategoryManager(context),
          ),
          const SizedBox(height: 16),

          // SMS Auto-Detection (Android only)
          if (!kIsWeb && platform.isAndroid) ...[
            _buildSectionTitle(context, 'Auto-Detect Transactions'),
            const SizedBox(height: 8),
            Consumer<SmsTransactionProvider>(
              builder: (context, smsProvider, _) {
                return Column(
                  children: [
                    _buildSettingTile(
                      context,
                      isDark: isDark,
                      icon: Icons.sms_rounded,
                      iconColor: AppTheme.accentTeal,
                      title: 'SMS Transaction Detection',
                      subtitle: smsProvider.smsFeatureEnabled
                          ? '${smsProvider.transactions.length} transactions detected'
                          : 'Auto-detect UPI payments from bank SMS',
                      trailing: Switch(
                        value: smsProvider.smsFeatureEnabled,
                        onChanged: (enabled) {
                          if (enabled) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SmsPermissionScreen(),
                              ),
                            );
                          } else {
                            smsProvider.disableFeature();
                          }
                        },
                        activeThumbColor: AppTheme.accentTeal,
                      ),
                    ),
                    if (smsProvider.smsFeatureEnabled)
                      _buildSettingTile(
                        context,
                        isDark: isDark,
                        icon: Icons.receipt_long_rounded,
                        iconColor: AppTheme.accentPurple,
                        title: 'View Detected Transactions',
                        subtitle: 'See auto-parsed UPI transactions',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SmsTransactionsScreen(),
                            ),
                          );
                        },
                      ),
                    _buildSettingTile(
                      context,
                      isDark: isDark,
                      icon: Icons.notifications_active_rounded,
                      iconColor: AppTheme.accentTeal,
                      title: 'Notification Detection',
                      subtitle: smsProvider.notificationAccessGranted
                          ? 'Enabled for UPI app alerts'
                          : 'Tap to enable notification access',
                      onTap: () => smsProvider.requestNotificationAccess(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // Export
          if (!kIsWeb) ...[
            _buildSectionTitle(context, 'Export Transactions'),
            const SizedBox(height: 8),
            _buildSettingTile(
              context,
              isDark: isDark,
              icon: Icons.table_chart_rounded,
              iconColor: AppTheme.incomeGreen,
              title: 'Export as CSV',
              subtitle: 'Spreadsheet format for Excel',
              onTap: () => _exportTransactions(context, 'csv'),
            ),
            _buildSettingTile(
              context,
              isDark: isDark,
              icon: Icons.picture_as_pdf_rounded,
              iconColor: AppTheme.expenseRed,
              title: 'Export as PDF',
              subtitle: 'Formatted report with summary',
              onTap: () => _exportTransactions(context, 'pdf'),
            ),
            const SizedBox(height: 16),
          ],

          // Haptic Feedback
          _buildSectionTitle(context, 'Accessibility'),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.vibration,
            iconColor: AppTheme.accentTeal,
            title: 'Haptic Feedback',
            subtitle: 'Vibration on key actions',
            trailing: Switch(
              value: HapticService.instance.isEnabled,
              onChanged: (value) {
                HapticService.instance.setEnabled(value);
                setState(() {});
                if (value) HapticService.instance.lightTap();
              },
              activeThumbColor: AppTheme.accentTeal,
            ),
          ),
          const SizedBox(height: 16),

          // Security
          _buildSectionTitle(context, 'Security'),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.fingerprint,
            iconColor: AppTheme.accentPurple,
            title: 'Biometric Lock',
            subtitle: BiometricService.instance.isEnabled
                ? 'Locks after ${BiometricService.instance.timeoutMinutes} min idle'
                : 'Protect your financial data',
            trailing: Switch(
              value: BiometricService.instance.isEnabled,
              onChanged: (value) async {
                HapticService.instance.lightTap();
                // Capture before any async gap
                final messenger = ScaffoldMessenger.of(context);
                if (value) {
                  // Check device support first
                  final canAuth = await BiometricService.instance
                      .canAuthenticate();
                  if (!canAuth) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Biometric authentication is not available on this device. '
                          'Please set up fingerprint or face unlock in your device settings.',
                        ),
                        duration: Duration(seconds: 4),
                      ),
                    );
                    return;
                  }
                  // Verify identity before enabling biometric lock
                  final authenticated = await BiometricService.instance
                      .authenticate(
                        reason: 'Verify your identity to enable biometric lock',
                      );
                  if (!authenticated) return;
                }
                await BiometricService.instance.setEnabled(value);
                if (mounted) setState(() {});
              },
              activeThumbColor: AppTheme.accentPurple,
            ),
          ),
          if (BiometricService.instance.isEnabled)
            _buildSettingTile(
              context,
              isDark: isDark,
              icon: Icons.timer_outlined,
              iconColor: AppTheme.textTertiary,
              title: 'Lock After',
              subtitle:
                  '${BiometricService.instance.timeoutMinutes} minutes of inactivity',
              onTap: () => _showTimeoutPicker(context),
            ),
          const SizedBox(height: 16),

          // Developer Options — DEBUG builds only.
          // Compile-time constant: entire block tree-shaken in release.
          if (kDebugMode) ...[
            _buildSectionTitle(context, 'Developer Options'),
            const SizedBox(height: 8),
            Consumer<PremiumProvider>(
              builder: (context, premium, _) {
                return _buildSettingTile(
                  context,
                  isDark: isDark,
                  icon: Icons.developer_mode_rounded,
                  iconColor: Colors.orange,
                  title: 'Developer Premium Access',
                  subtitle: premium.isDeveloperPremiumAccessEnabled
                      ? 'ON \u2014 All premium features unlocked'
                      : 'OFF \u2014 Using real RevenueCat entitlements',
                  trailing: Switch(
                    value: premium.isDeveloperPremiumAccessEnabled,
                    activeThumbColor: Colors.orange,
                    onChanged: (v) => premium.setDeveloperPremiumAccess(v),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // About
          _buildSectionTitle(context, 'About'),
          const SizedBox(height: 8),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.pets,
            iconColor: AppTheme.accentTeal,
            title: 'P.E.T',
            subtitle: 'Personal Expense Tracker v1.0.1',
          ),
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.info_outline,
            iconColor: AppTheme.textTertiary,
            title: 'Made with ❤️ for India',
            subtitle: 'Track expenses in ₹ with UPI & Cards',
          ),
          const SizedBox(height: 16),

          // Sign out
          _buildSettingTile(
            context,
            isDark: isDark,
            icon: Icons.logout_rounded,
            iconColor: AppTheme.expenseRed,
            title: 'Sign Out',
            subtitle: 'Clear profile and sign out',
            onTap: () => _signOut(context),
          ),
          _buildDangerZoneSection(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildDangerZoneSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Danger Zone',
            style: TextStyle(
              color: Colors.red.shade400,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red.shade300, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Icon(
              Icons.delete_forever_rounded,
              color: Colors.red.shade400,
            ),
            title: Text(
              'Delete Account',
              style: TextStyle(
                color: Colors.red.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Permanently delete your account and all data',
              style: TextStyle(fontSize: 12),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: Colors.red.shade300,
            ),
            onTap: () => _startAccountDeletion(context),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _startAccountDeletion(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const AccountDeletionSheet(),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildThemePicker(
    BuildContext context,
    bool isDark,
    ThemeMode currentMode,
  ) {
    Widget option(ThemeMode mode, IconData icon, String label) {
      final isSelected = currentMode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            ThemeModeNotifier.of(context).onThemeModeChanged(mode);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accentPurple.withAlpha(isDark ? 50 : 30)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accentPurple.withAlpha(120)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? AppTheme.accentPurple
                      : (isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.accentPurple
                        : (isDark
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondaryLight),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          option(ThemeMode.system, Icons.brightness_auto, 'System'),
          const SizedBox(width: 4),
          option(ThemeMode.light, Icons.light_mode, 'Light'),
          const SizedBox(width: 4),
          option(ThemeMode.dark, Icons.dark_mode, 'Dark'),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(15)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  void _showCategoryManager(BuildContext context) {
    final catProvider = context.read<CategoryProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.cardDark
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final customCategories = catProvider.categories
                .where((c) => c.isCustom)
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Custom Categories',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () =>
                                _showAddCategoryDialog(context, catProvider),
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppTheme.accentPurple,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (customCategories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No custom categories yet. Tap + to add one.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  else
                    ...customCategories.map(
                      (cat) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.surfaceDark
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(cat.icon, color: cat.color, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                cat.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              cat.type,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            IconButton(
                              onPressed: () {
                                catProvider.deleteCategory(cat.id);
                                setSheetState(() {});
                              },
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppTheme.expenseRed,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddCategoryDialog(
    BuildContext context,
    CategoryProvider catProvider,
  ) {
    final nameController = TextEditingController();
    String type = 'expense';
    Color selectedColor = AppTheme.accentPurple;
    IconData selectedIcon = Icons.category;

    final colorOptions = [
      const Color(0xFFFF6B6B),
      const Color(0xFF4ECDC4),
      const Color(0xFFFFE66D),
      const Color(0xFFA78BFA),
      const Color(0xFF22D3EE),
      const Color(0xFFF472B6),
      const Color(0xFF60A5FA),
      const Color(0xFF34D399),
      const Color(0xFFFB923C),
      const Color(0xFF818CF8),
    ];

    final iconOptions = [
      Icons.category,
      Icons.star,
      Icons.favorite,
      Icons.sports_esports,
      Icons.pets,
      Icons.flight,
      Icons.local_cafe,
      Icons.fitness_center,
      Icons.music_note,
      Icons.book,
      Icons.construction,
      Icons.devices,
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Category'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Category Name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Type'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Expense'),
                          selected: type == 'expense',
                          onSelected: (_) {
                            setDialogState(() => type = 'expense');
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Income'),
                          selected: type == 'income',
                          onSelected: (_) {
                            setDialogState(() => type = 'income');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Color'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colorOptions.map((color) {
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedColor = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: selectedColor == color
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Icon'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: iconOptions.map((icon) {
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedIcon = icon),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: selectedIcon == icon
                                  ? selectedColor.withAlpha(40)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: selectedIcon == icon
                                  ? Border.all(color: selectedColor)
                                  : null,
                            ),
                            child: Icon(
                              icon,
                              color: selectedIcon == icon
                                  ? selectedColor
                                  : null,
                              size: 22,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      catProvider.addCustomCategory(
                        name: nameController.text,
                        icon: selectedIcon,
                        color: selectedColor,
                        type: type,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileCard(BuildContext context, bool isDark) {
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : '?';
    final photoUrl = AuthService.photoUrl;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withAlpha(60), width: 2),
            ),
            child: ClipOval(
              child: photoUrl != null
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) => Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail,
                  style: TextStyle(
                    color: Colors.white.withAlpha(180),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.verified_rounded,
            color: Colors.white.withAlpha(200),
            size: 22,
          ),
        ],
      ),
    );
  }

  Future<void> _exportTransactions(BuildContext context, String format) async {
    final txnProvider = context.read<TransactionProvider>();
    final allTxns = txnProvider.allTransactions;

    if (allTxns.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transactions to export')),
        );
      }
      return;
    }

    // Require biometric authentication before export if App Lock is enabled
    if (BiometricService.instance.isEnabled) {
      final authenticated = await BiometricService.instance.authenticate(
        reason: 'Verify identity to export transactions',
      );
      if (!authenticated) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication failed. Export cancelled.')),
          );
        }
        return;
      }
    }

    if (!context.mounted) return;
    final categoryProvider = context.read<CategoryProvider>();
    final categoryNames = {
      for (final cat in categoryProvider.categories) cat.id: cat.name
    };

    // Quick date range picker using the current financial year
    final now = DateTime.now();
    final fyStart = now.month >= 4
        ? DateTime(now.year, 4, 1)
        : DateTime(now.year - 1, 4, 1);
    final fyEnd = now;

    try {
      if (format == 'csv') {
        await ExportService.instance.exportToCsv(
          allTxns,
          startDate: fyStart,
          endDate: fyEnd,
          categoryNames: categoryNames,
        );
      } else {
        await ExportService.instance.exportToPdf(
          allTxns,
          startDate: fyStart,
          endDate: fyEnd,
          categoryNames: categoryNames,
        );
      }
    } catch (e) {
      AppLogger.debug('[Export] Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _showTimeoutPicker(BuildContext context) {
    final options = [1, 5, 15, 30];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Lock After'),
        children: options.map((min) {
          final isSelected = BiometricService.instance.timeoutMinutes == min;
          return SimpleDialogOption(
            onPressed: () {
              BiometricService.instance.setTimeoutMinutes(min);
              setState(() {});
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                if (isSelected)
                  const Icon(
                    Icons.check,
                    size: 18,
                    color: AppTheme.accentPurple,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 12),
                Text(
                  '$min ${min == 1 ? 'minute' : 'minutes'}',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected ? AppTheme.accentPurple : null,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out? Your data will remain on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.expenseRed),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!context.mounted) return;

    try {
      // Cache providers before making async calls.
      final transactionProvider = context.read<TransactionProvider>();
      final categoryProvider = context.read<CategoryProvider>();
      final budgetProvider = context.read<BudgetProvider>();
      final premiumProvider = context.read<PremiumProvider>();

      // Clear all provider state BEFORE signing out so no stale data
      // remains in memory or SQLite when a different account signs in.
      await transactionProvider.clearData();
      await categoryProvider.clearData();
      await budgetProvider.clearData();
      await premiumProvider.clearData();

      await AuthService.signOut();

      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const GoogleSignInScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign out failed: ${e.toString()}'),
            backgroundColor: AppTheme.expenseRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}
