import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/providers/linked_account_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinkedAccountProvider Production Safety', () {
    test('isTesting defaults to false and connectMockAccount throws in production', () async {
      final provider = LinkedAccountProvider();

      expect(provider.isTesting, isFalse);
      expect(
        () => provider.connectMockAccount(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
