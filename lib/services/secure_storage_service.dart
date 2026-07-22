import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pet/core/utils/app_logger.dart';

/// Service for managing secrets and encryption keys securely.
///
/// Uses `flutter_secure_storage` to write, read, and delete sensitive data at rest
/// leveraging Keychain (iOS), Keystore (Android), and Credential Manager (Windows).
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const String _kDbEncryptionKey = 'db_encryption_key';

  /// Read a value from secure storage.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      AppLogger.error('[SecureStorage] Error reading key "$key"', error: e);
      return null;
    }
  }

  /// Write a value to secure storage.
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      AppLogger.error('[SecureStorage] Error writing key "$key"', error: e);
    }
  }

  /// Delete a key from secure storage.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      AppLogger.error('[SecureStorage] Error deleting key "$key"', error: e);
    }
  }

  /// Check if a key exists in secure storage.
  Future<bool> containsKey(String key) async {
    try {
      final all = await _storage.readAll();
      return all.containsKey(key);
    } catch (e) {
      AppLogger.error('[SecureStorage] Error checking key "$key"', error: e);
      return false;
    }
  }

  /// Clear all keys in secure storage.
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      AppLogger.error('[SecureStorage] Error clearing storage', error: e);
    }
  }

  /// Retrieve or generate the cryptographically secure 256-bit database encryption key.
  Future<String> getDatabaseEncryptionKey() async {
    var key = await read(_kDbEncryptionKey);
    if (key == null || key.isEmpty) {
      AppLogger.info('[SecureStorage] No existing database key found. Generating new secure key.');
      key = _generateSecureRandomKey();
      await write(_kDbEncryptionKey, key);
    }
    return key;
  }

  /// Generates a cryptographically strong 256-bit (32-byte) key.
  String _generateSecureRandomKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
}
