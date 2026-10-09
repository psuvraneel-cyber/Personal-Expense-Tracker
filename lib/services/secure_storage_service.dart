import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pet/core/utils/app_logger.dart';

/// Thrown when the local database exists but its encryption key cannot be
/// read (Keystore error) or is missing. The key must NOT be regenerated in
/// this case — that would make the existing database permanently unreadable.
class DatabaseKeyUnavailableException implements Exception {
  final String message;
  final Object? cause;
  DatabaseKeyUnavailableException(this.message, [this.cause]);
  @override
  String toString() => 'DatabaseKeyUnavailableException: $message';
}

/// Service for managing secrets and encryption keys securely.
///
/// Uses `flutter_secure_storage` to write, read, and delete sensitive data at rest
/// leveraging Keychain (iOS), Keystore (Android), and Credential Manager (Windows).
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      // Never silently wipe secrets on a decryption error: that would destroy
      // the database key. Errors surface as DatabaseKeyUnavailableException
      // and the app offers an explicit recovery instead.
      resetOnError: false,
      migrateOnAlgorithmChange: true,
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

  /// Retrieve or generate the cryptographically secure 256-bit database
  /// encryption key.
  ///
  /// A new key is generated **only** when no encrypted database exists yet
  /// ([databaseExists] is false). If storage throws, or the key is missing
  /// while a database exists, [DatabaseKeyUnavailableException] is thrown so
  /// the app can offer recovery instead of silently destroying access.
  Future<String> getDatabaseEncryptionKey({bool databaseExists = false}) async {
    String? key;
    try {
      key = await _storage.read(key: _kDbEncryptionKey);
    } catch (e) {
      throw DatabaseKeyUnavailableException(
        'Secure storage could not be read',
        e,
      );
    }
    if (key != null && key.isNotEmpty) return key;

    if (databaseExists) {
      throw DatabaseKeyUnavailableException(
        'Encryption key missing for an existing database',
      );
    }

    AppLogger.info(
      '[SecureStorage] No existing database key found. Generating new secure key.',
    );
    key = _generateSecureRandomKey();
    await _storage.write(key: _kDbEncryptionKey, value: key);
    return key;
  }

  /// Removes the database key (used only by the explicit "reset local data"
  /// recovery action, together with deleting the database file).
  Future<void> deleteDatabaseEncryptionKey() => delete(_kDbEncryptionKey);

  /// Generates a cryptographically strong 256-bit (32-byte) key.
  String _generateSecureRandomKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
}
