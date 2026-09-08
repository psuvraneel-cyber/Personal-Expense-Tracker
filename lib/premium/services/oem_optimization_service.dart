import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/utils/app_logger.dart';

/// Service to detect aggressive Android OEMs (Xiaomi/MIUI/HyperOS, Samsung OneUI,
/// Oppo/ColorOS, Vivo/FuntouchOS, etc.) and provide a best-effort fallback intent
/// chain to open autostart / battery optimization settings.
class OemOptimizationService {
  static const String _prefPromptShown = 'oem_battery_prompt_shown';

  static final OemOptimizationService instance = OemOptimizationService._();
  OemOptimizationService._();

  /// Known aggressive OEM manufacturers / brands that restrict background isolates and WorkManager.
  static const List<String> aggressiveOems = [
    'xiaomi',
    'redmi',
    'poco',
    'oppo',
    'realme',
    'vivo',
    'iqoo',
    'huawei',
    'honor',
    'samsung',
    'oneplus',
    'infinix',
    'tecno',
  ];

  /// Pure helper to check if a manufacturer/brand string matches aggressive OEMs.
  static bool isManufacturerAggressive(String manufacturerOrBrand) {
    final lower = manufacturerOrBrand.toLowerCase();
    return aggressiveOems.any((oem) => lower.contains(oem));
  }

  /// Reads the actual application package ID at runtime via package_info_plus.
  Future<String> getPackageName() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.packageName.isNotEmpty) {
        return info.packageName;
      }
    } catch (e) {
      AppLogger.debug('[OemOptimizationService] Failed to read package info: $e');
    }
    return 'com.pet.tracker.pet';
  }

  /// Checks if the current device is Android and running on an aggressive OEM build.
  Future<bool> isAggressiveOem() async {
    if (!Platform.isAndroid) return false;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      final brand = androidInfo.brand.toLowerCase();

      final matches =
          isManufacturerAggressive(manufacturer) ||
          isManufacturerAggressive(brand);
      AppLogger.debug(
        '[OemOptimizationService] Manufacturer: $manufacturer, Brand: $brand -> Aggressive OEM: $matches',
      );
      return matches;
    } catch (e) {
      AppLogger.debug(
        '[OemOptimizationService] Error reading device info: $e',
      );
      return false;
    }
  }

  /// Returns whether the one-time battery optimization prompt has already been shown.
  Future<bool> hasPromptBeenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPromptShown) ?? false;
  }

  /// Marks the battery optimization prompt as shown.
  Future<void> markPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPromptShown, true);
  }

  /// Executes a best-effort intent fallback chain to open battery / autostart settings.
  ///
  /// Chain:
  /// 1. OEM-specific autostart/battery settings intent (Samsung OneUI 6, Xiaomi HyperOS/MIUI, etc.).
  /// 2. Generic `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`.
  /// 3. Generic `Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
  /// 4. Generic `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`.
  Future<bool> openOptimizationSettings() async {
    if (!Platform.isAndroid) return false;

    final deviceInfo = DeviceInfoPlugin();
    String manufacturer = '';
    try {
      final androidInfo = await deviceInfo.androidInfo;
      manufacturer = androidInfo.manufacturer.toLowerCase();
    } catch (_) {}

    final packageName = await getPackageName();

    // ── 1. Try OEM-Specific Autostart / Battery Intents (with fallbacks) ─────
    bool success = await _tryOemSpecificIntent(manufacturer, packageName);
    if (success) return true;

    // ── 2. Fallback to Generic Ignore Battery Optimization Settings ─────────
    success = await _tryGenericBatteryOptimizationSettings();
    if (success) return true;

    // ── 3. Fallback to Request Ignore Battery Optimization with Data URI ────
    success = await _tryRequestIgnoreBatteryOptimization(packageName);
    if (success) return true;

    // ── 4. Final Fallback to App Details Settings ───────────────────────────
    return await _tryAppDetailsSettings(packageName);
  }

  List<AndroidIntent> _getOemIntents(String manufacturer, String packageName) {
    if (manufacturer.contains('xiaomi') ||
        manufacturer.contains('redmi') ||
        manufacturer.contains('poco')) {
      return [
        // Xiaomi MIUI / HyperOS AutoStart Activity
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.miui.securitycenter',
          componentName:
              'com.miui.permcenter.autostart.AutoStartManagementActivity',
        ),
        // Xiaomi HyperOS / MIUI PowerSettings
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.miui.securitycenter',
          componentName: 'com.miui.powercenter.PowerSettings',
        ),
        // Xiaomi HyperOS / MIUI Power Hide Mode App List
        AndroidIntent(
          action: 'miui.intent.action.POWER_HIDE_MODE_APP_LIST',
          arguments: <String, dynamic>{'package_name': packageName},
        ),
        // Xiaomi HyperOS / MIUI OP AutoStart
        AndroidIntent(
          action: 'miui.intent.action.OP_AUTO_START',
          arguments: <String, dynamic>{'package_name': packageName},
        ),
      ];
    } else if (manufacturer.contains('samsung')) {
      return [
        // Samsung OneUI 4 / 5 / 6 Device Care Battery Activity
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.samsung.android.sm',
          componentName: 'com.samsung.android.sm.ui.battery.BatteryActivity',
        ),
        // Samsung OneUI Battery variant
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.samsung.android.sm',
          componentName: 'com.samsung.android.sm.battery.ui.BatteryActivity',
        ),
        // Samsung Device Care App Sleep List
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.samsung.android.sm',
          componentName: 'com.samsung.android.sm.ui.battery.AppSleepListActivity',
        ),
        // Samsung CN variant
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.samsung.android.sm_cn',
          componentName: 'com.samsung.android.sm.ui.battery.BatteryActivity',
        ),
        // Samsung Legacy Smart Manager
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.samsung.android.looper',
        ),
      ];
    } else if (manufacturer.contains('oppo') ||
        manufacturer.contains('realme')) {
      return [
        // Oppo / Realme ColorOS Permission Single Page
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.coloros.safecenter',
          componentName:
              'com.coloros.safecenter.permission.singlepage.PermissionSinglePageActivity',
        ),
        // ColorOS Startup App List
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.coloros.safecenter',
          componentName:
              'com.coloros.safecenter.startupapp.StartupAppListActivity',
        ),
        // OPlus SafeCenter Startup App List
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.oplus.safecenter',
          componentName:
              'com.oplus.safecenter.startupapp.StartupAppListActivity',
        ),
        // ColorOS Oppoguardelf Power Manager
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.coloros.oppoguardelf',
        ),
      ];
    } else if (manufacturer.contains('vivo') ||
        manufacturer.contains('iqoo')) {
      return [
        // Vivo / iQOO Add Whitelist
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.iqoo.secure',
          componentName: 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity',
        ),
        // Vivo / iQOO Bg Start Up Manager
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.iqoo.secure',
          componentName: 'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager',
        ),
        // Vivo Permission Manager Background Startup Activity
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.vivo.permissionmanager',
          componentName:
              'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        ),
        // Vivo ABE Excessive Power Manager
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.vivo.abe',
          componentName:
              'com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity',
        ),
      ];
    } else if (manufacturer.contains('huawei') ||
        manufacturer.contains('honor')) {
      return [
        // Huawei Startup Normal App List
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.huawei.systemmanager',
          componentName:
              'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
        ),
        // Huawei Optimize Process Protect Activity
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.huawei.systemmanager',
          componentName:
              'com.huawei.systemmanager.optimize.process.ProtectActivity',
        ),
        // Huawei App Control Startup
        const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.huawei.systemmanager',
          componentName:
              'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity',
        ),
      ];
    }
    return const [];
  }

  Future<bool> _tryOemSpecificIntent(
    String manufacturer,
    String packageName,
  ) async {
    final intents = _getOemIntents(manufacturer, packageName);
    for (final intent in intents) {
      try {
        await intent.launch();
        return true;
      } catch (e) {
        AppLogger.debug(
          '[OemOptimizationService] OEM intent attempt failed (${intent.package ?? intent.action}): $e',
        );
      }
    }
    return false;
  }

  Future<bool> _tryGenericBatteryOptimizationSettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );
      await intent.launch();
      return true;
    } catch (e) {
      AppLogger.debug(
        '[OemOptimizationService] Generic battery settings intent failed: $e',
      );
    }
    return false;
  }

  Future<bool> _tryRequestIgnoreBatteryOptimization(String packageName) async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$packageName',
      );
      await intent.launch();
      return true;
    } catch (e) {
      AppLogger.debug(
        '[OemOptimizationService] Request ignore battery optimization failed: $e',
      );
    }
    return false;
  }

  Future<bool> _tryAppDetailsSettings(String packageName) async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$packageName',
      );
      await intent.launch();
      return true;
    } catch (e) {
      AppLogger.debug(
        '[OemOptimizationService] App details settings intent failed: $e',
      );
    }
    return false;
  }
}
