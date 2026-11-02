import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/counterparty_classifier.dart';

void main() {
  CounterpartyType classify(String name, {String? upi, String channel = ''}) =>
      CounterpartyClassifier.classify(
          payeeName: name, upiId: upi, channel: channel);

  group('companies and brands', () {
    test('known brands', () {
      for (final name in [
        'SWIGGY',
        'Zomato Ltd',
        'APOLLO PHARMACY',
        'Blinkit',
        'Amazon Pay',
      ]) {
        expect(classify(name), CounterpartyType.company, reason: name);
      }
    });

    test('legal entities', () {
      for (final name in [
        'ACME TECHNOLOGIES PVT LTD',
        'Sunrise Insurance Limited',
        'Bright Ventures LLP',
      ]) {
        expect(classify(name), CounterpartyType.company, reason: name);
      }
    });

    test('a brand behind a UPI ID', () {
      expect(classify('Unknown', upi: 'swiggy@icici'),
          CounterpartyType.company);
    });
  });

  group('shops', () {
    test('trade words in the name', () {
      for (final name in [
        'SHARMA KIRANA STORE',
        'Balaji Medicals',
        'Gupta Sweets',
        'New Royal Bakery',
        'Raju Tea Stall Shop',
      ]) {
        expect(classify(name), CounterpartyType.shop, reason: name);
      }
    });

    test('merchant QR / business UPI IDs', () {
      for (final upi in [
        'paytmqr2810050501011abcd@paytm',
        'Q123456789@ybl',
        'bharatpe.9000012345@fbpe',
        'gpay-11234567890@okbizaxis',
      ]) {
        expect(classify('Unknown', upi: upi), CounterpartyType.shop,
            reason: upi);
      }
    });

    test('card / POS payments', () {
      expect(classify('RELIANCE SMART', channel: 'CARD'),
          CounterpartyType.shop);
    });
  });

  group('people', () {
    test('phone-number UPI IDs', () {
      expect(classify('Unknown', upi: '9876543210@ybl'),
          CounterpartyType.person);
      expect(classify('Unknown', upi: '919812345678@paytm'),
          CounterpartyType.person);
    });

    test('names of individuals', () {
      for (final name in [
        'SUNITA DEVI',
        'Rahul Kumar',
        'Mr R Sharma',
        'PRIYA S',
      ]) {
        expect(classify(name), CounterpartyType.person, reason: name);
      }
    });

    test('a name with a trade word is a shop, not a person', () {
      expect(classify('RAMESH GENERAL STORE'), CounterpartyType.shop);
    });
  });

  group('not enough to tell', () {
    test('single words, payment words and unknowns', () {
      for (final name in ['SWEETHOME', 'UPI TRANSFER', 'Unknown', '']) {
        expect(classify(name), CounterpartyType.unknown, reason: name);
      }
    });
  });

  test('salary credits are from a company', () {
    expect(
      CounterpartyClassifier.classify(
        payeeName: 'RAHUL KUMAR',
        text: 'Salary of Rs 50,000 credited to A/c XX1234',
      ),
      CounterpartyType.company,
    );
  });
}
