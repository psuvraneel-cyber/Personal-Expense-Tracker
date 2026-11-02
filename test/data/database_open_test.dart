import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('db_open_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('isPlaintextDatabaseFile', () {
    test('an unencrypted SQLite file is detected', () async {
      final path = p.join(dir.path, 'plain.db');
      final db = await openDatabase(path);
      await db.execute('CREATE TABLE t (x INTEGER)');
      await db.close();
      expect(await DatabaseHelper.isPlaintextDatabaseFile(path), isTrue);
    });

    test('an encrypted (random-looking) file, a short file or none is not',
        () async {
      final encrypted = File(p.join(dir.path, 'enc.db'));
      final r = Random(1);
      await encrypted.writeAsBytes(List.generate(4096, (_) => r.nextInt(256)));
      expect(await DatabaseHelper.isPlaintextDatabaseFile(encrypted.path),
          isFalse);

      final short = File(p.join(dir.path, 'short.db'));
      await short.writeAsBytes('SQLite'.codeUnits);
      expect(await DatabaseHelper.isPlaintextDatabaseFile(short.path), isFalse);

      expect(
        await DatabaseHelper.isPlaintextDatabaseFile(p.join(dir.path, 'none')),
        isFalse,
      );
    });
  });

  group('retryWhileLocked', () {
    const noDelay = [Duration.zero, Duration.zero, Duration.zero];

    test('retries while another isolate holds the lock, then succeeds',
        () async {
      var calls = 0;
      final result = await DatabaseHelper.retryWhileLocked(() async {
        calls++;
        if (calls < 3) {
          throw Exception('DatabaseException(database is locked (code 5))');
        }
        return 'opened';
      }, delays: noDelay);
      expect(result, 'opened');
      expect(calls, 3);
    });

    test('other errors are not retried', () async {
      var calls = 0;
      await expectLater(
        DatabaseHelper.retryWhileLocked<void>(() async {
          calls++;
          throw Exception('file is not a database');
        }, delays: noDelay),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });

    test('gives up after the last retry', () async {
      var calls = 0;
      await expectLater(
        DatabaseHelper.retryWhileLocked<void>(() async {
          calls++;
          throw Exception('database is locked');
        }, delays: noDelay),
        throwsA(isA<Exception>()),
      );
      expect(calls, noDelay.length + 1);
    });
  });
}
