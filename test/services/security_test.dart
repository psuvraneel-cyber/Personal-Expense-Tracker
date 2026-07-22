import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/services/secure_storage_service.dart';
import 'package:pet/services/firebase_auth_service.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ignore: subtype_of_sealed_class
class FakeFirebaseAuth implements FirebaseAuth {
  final User? _currentUser;
  FakeFirebaseAuth({User? currentUser}) : _currentUser = currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStorageMap = <String, String>{};

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Set up Mock handler for flutter_secure_storage method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments as Map?;
        switch (methodCall.method) {
          case 'write':
            if (args != null) {
              secureStorageMap[args['key'] as String] = args['value'] as String;
            }
            return null;
          case 'read':
            if (args != null) {
              return secureStorageMap[args['key'] as String];
            }
            return null;
          case 'delete':
            if (args != null) {
              secureStorageMap.remove(args['key'] as String);
            }
            return null;
          case 'readAll':
            return secureStorageMap;
          case 'deleteAll':
            secureStorageMap.clear();
            return null;
          case 'containsKey':
            if (args != null) {
              return secureStorageMap.containsKey(args['key'] as String);
            }
            return false;
          default:
            return null;
        }
      },
    );
  });

  setUp(() {
    secureStorageMap.clear();
    SharedPreferences.setMockInitialValues({});
  });

  group('SecureStorageService Tests', () {
    test('getDatabaseEncryptionKey generates a secure 256-bit key on first call', () async {
      final key = await SecureStorageService.instance.getDatabaseEncryptionKey();
      expect(key, isNotEmpty);
      // Base64Url representation of 32 bytes should be 43 characters long without padding
      expect(key.length, greaterThanOrEqualTo(43));
      expect(secureStorageMap['db_encryption_key'], equals(key));
    });

    test('getDatabaseEncryptionKey retrieves the same key on subsequent calls', () async {
      final key1 = await SecureStorageService.instance.getDatabaseEncryptionKey();
      final key2 = await SecureStorageService.instance.getDatabaseEncryptionKey();
      expect(key1, equals(key2));
    });
  });

  group('FirebaseAuthService Secure Migration Tests', () {
    test('tryRestoreSession migrates legacy SharedPreferences credentials to SecureStorage', () async {
      // 1. Setup legacy credentials in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', 'Test User');
      await prefs.setString('userEmail', 'test@example.com');
      await prefs.setBool('isLocalGuest', true);

      final authService = FirebaseAuthService();
      authService.firebaseAuth = FakeFirebaseAuth();
      
      // 2. Trigger session restore which runs migration
      final restored = await authService.tryRestoreSession();
      expect(restored, isTrue);

      // 3. Verify SharedPreferences values were cleaned up
      expect(prefs.containsKey('userName'), isFalse);
      expect(prefs.containsKey('userEmail'), isFalse);

      // 4. Verify values now reside in SecureStorage
      expect(secureStorageMap['userName'], equals('Test User'));
      expect(secureStorageMap['userEmail'], equals('test@example.com'));
      expect(authService.userName, equals('Test User'));
    });
  });

  group('DatabaseHelper Encryption Gating Tests', () {
    test('isSqlCipherSupported returns false when using FFI on standard Windows test environment', () async {
      final helper = DatabaseHelper();
      final cipherSupported = await helper.isSqlCipherSupported();
      // On standard Windows test FFI environments (uncompiled DLL), cipher is not supported
      expect(cipherSupported, isFalse);
    });
  });
}
