import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:pet/services/app_bootstrap.dart';

/// Authenticated calls to the P.E.T Cloudflare Worker (AI Copilot, free
/// allowance, referrals). Sends the Firebase ID token and, when available,
/// an App Check token.
class WorkerApi {
  WorkerApi._();

  static const baseUrl = 'https://pet-ai-copilot.pet-app.workers.dev';

  static Future<http.Response> post(
    String path,
    Map<String, Object?> body, {
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Login required.');
    }

    final idToken = await user.getIdToken(forceRefresh);
    if (idToken == null) {
      throw Exception('Failed to get authentication token.');
    }

    final appCheckToken = await AppBootstrap.appCheckToken();
    return http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
            if (appCheckToken != null) 'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
  }
}
