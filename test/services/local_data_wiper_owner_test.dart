import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/services/local_data_wiper.dart';
import 'package:pet/services/session_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

class _WipeDb implements DatabaseHelper {
  _WipeDb({required this.fails});
  final bool fails;

  @override
  Future<void> wipeAllUserData({Database? db}) async {
    if (fails) throw StateError('database is locked');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A failed database wipe must not let the next account see the old rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a clean wipe leaves the data unowned', () async {
    SharedPreferences.setMockInitialValues({DataOwner.prefKey: 'alice'});
    await LocalDataWiper.wipe(dbHelper: _WipeDb(fails: false));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DataOwner.prefKey), isNull);
    expect(await DataOwner.isOwnedBy('bob'), isTrue);
  });

  test('a failed database wipe keeps the owner, so bob is refused', () async {
    SharedPreferences.setMockInitialValues({DataOwner.prefKey: 'alice'});
    await LocalDataWiper.wipe(dbHelper: _WipeDb(fails: true));
    expect(await DataOwner.isOwnedBy('bob'), isFalse);
  });
}
