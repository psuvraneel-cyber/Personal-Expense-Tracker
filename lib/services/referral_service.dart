import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pet/services/worker_api.dart';

/// Outcome of redeeming an invite code.
class ReferralResult {
  const ReferralResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

/// "Invite a friend, you both get a month of Premium." Codes are issued and
/// redeemed by the Worker, which grants the months through RevenueCat.
class ReferralService {
  ReferralService._();

  /// The signed-in user's own invite code, or null if unavailable.
  static Future<String?> myCode() async {
    try {
      final res = await WorkerApi.post('/referral/code', const {});
      if (res.statusCode != 200) return null;
      final code = (jsonDecode(res.body) as Map)['code'];
      return code is String ? code : null;
    } catch (_) {
      return null;
    }
  }

  static Future<ReferralResult> redeem(String code) async {
    try {
      final res = await WorkerApi.post('/referral/redeem', {'code': code});
      return resultFor(res.statusCode, res.body);
    } catch (_) {
      return const ReferralResult(
        ok: false,
        message: "Couldn't reach P.E.T. Check your connection and try again.",
      );
    }
  }

  @visibleForTesting
  static ReferralResult resultFor(int status, String body) {
    if (status == 200) {
      return const ReferralResult(
        ok: true,
        message: 'Done! You have a free month of Premium. '
            'Your friend gets one too.',
      );
    }
    String? code;
    try {
      code = (jsonDecode(body) as Map)['errorCode']?.toString();
    } catch (_) {}
    final message = switch (code) {
      'INVALID_CODE' => "That invite code isn't valid. Check it and try again.",
      'OWN_CODE' => "You can't use your own invite code.",
      'ALREADY_REDEEMED' => "You've already used an invite code.",
      'NOT_NEW_USER' => 'Invite codes are for people new to P.E.T.',
      'SIGN_IN_REQUIRED' => 'Sign in with Google to use an invite code.',
      _ => "Couldn't apply the code right now. Please try again.",
    };
    return ReferralResult(ok: false, message: message);
  }

  /// Account deletion: asks the Worker to delete what it stored for this
  /// account (referral records, free AI question counters). Best effort:
  /// returns false if the Worker couldn't be reached.
  static Future<bool> forgetMe() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await WorkerApi.post('/referral/forget', const {});
        if (res.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Message shared with friends.
  static String shareText(String code, String storeLink) =>
      'I track my spending automatically with P.E.T. Use my invite code '
      '$code in the app (Settings → Invite friends) and we both get a month '
      'of Premium free: $storeLink';
}
