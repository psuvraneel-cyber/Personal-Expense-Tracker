import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/services/invoice_reminder_message.dart';
import 'package:pet/premium/services/invoice_reminder_scheduler.dart';

void main() {
  final invoice = Invoice(
    id: 'i1',
    number: 'INV/26-27/0001',
    billTo: const BillTo(name: 'Acme Traders', phone: '98765 43210'),
    issueDate: DateTime(2026, 11, 1),
    dueDate: DateTime(2026, 11, 15),
    status: InvoiceStatus.sent,
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );
  const profile =
      InvoiceProfile(businessName: 'Alice Studio', upiId: 'alice@okaxis');

  String message(DateTime now) => InvoiceReminderMessage.build(
        invoice,
        profile,
        balance: 29500,
        now: now,
      );

  group('message', () {
    test('before the due date', () {
      final m = message(DateTime(2026, 11, 10));
      expect(m, startsWith('Hi Acme Traders,'));
      expect(m, contains('INV/26-27/0001 for ₹29,500 is due on 15 Nov 2026.'));
      expect(m, contains('pay by UPI to alice@okaxis'));
      expect(m, endsWith('Alice Studio'));
    });

    test('on the due date', () {
      expect(message(DateTime(2026, 11, 15, 18)), contains('is due today.'));
    });

    test('overdue says so', () {
      expect(
        message(DateTime(2026, 11, 20)),
        contains('was due on 15 Nov 2026 and is still unpaid.'),
      );
    });

    test('no UPI ID, no UPI line', () {
      final m = InvoiceReminderMessage.build(
        invoice,
        const InvoiceProfile(businessName: 'Alice Studio'),
        balance: 100,
        now: DateTime(2026, 11, 10),
      );
      expect(m, isNot(contains('UPI')));
    });
  });

  group('phone numbers', () {
    test('Indian numbers get the country code', () {
      expect(InvoiceReminderMessage.internationalNumber('98765 43210'),
          '919876543210');
      expect(InvoiceReminderMessage.internationalNumber('098765-43210'),
          '919876543210');
      expect(InvoiceReminderMessage.internationalNumber('+91 98765 43210'),
          '919876543210');
    });

    test('foreign numbers are kept; junk is rejected', () {
      expect(InvoiceReminderMessage.internationalNumber('+1 415 555 2671'),
          '14155552671');
      expect(InvoiceReminderMessage.internationalNumber(''), isNull);
      expect(InvoiceReminderMessage.internationalNumber('12345'), isNull);
    });

    test('links carry the number and the message', () {
      final wa = InvoiceReminderMessage.whatsApp('9876543210', 'Hi & thanks')!;
      expect(wa.host, 'wa.me');
      expect(wa.path, '/919876543210');
      expect(wa.queryParameters['text'], 'Hi & thanks');

      final sms = InvoiceReminderMessage.sms('9876543210', 'Hi & thanks')!;
      expect(sms.scheme, 'sms');
      expect(sms.toString(), contains('+919876543210'));
      expect(sms.toString(), contains('Hi%20%26%20thanks'));

      expect(InvoiceReminderMessage.whatsApp('', 'x'), isNull);
      expect(InvoiceReminderMessage.sms('', 'x'), isNull);
    });
  });

  test('reminders fire at 10:00 on the due date and three days later', () {
    final t = InvoiceReminderScheduler.timesFor(invoice);
    expect(t.due, DateTime(2026, 11, 15, 10));
    expect(t.overdue, DateTime(2026, 11, 18, 10));
  });
}
