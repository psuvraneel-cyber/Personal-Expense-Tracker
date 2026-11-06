import 'package:intl/intl.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';

/// The polite "please pay" message the user can send a client. P.E.T only
/// prepares it: the user reads it and sends it from their own app.
class InvoiceReminderMessage {
  InvoiceReminderMessage._();

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _date = DateFormat('d MMM yyyy');

  static String build(
    Invoice invoice,
    InvoiceProfile profile, {
    required double balance,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(
        invoice.dueDate.year, invoice.dueDate.month, invoice.dueDate.day);
    final amount = _money.format(balance);
    final lead = 'invoice ${invoice.number} for $amount';
    final String when;
    if (due.isBefore(today)) {
      when = 'A quick reminder that $lead was due on ${_date.format(due)} '
          'and is still unpaid.';
    } else if (due == today) {
      when = 'A quick reminder that $lead is due today.';
    } else {
      when = 'A quick reminder that $lead is due on ${_date.format(due)}.';
    }
    return [
      'Hi ${invoice.billTo.name},',
      '',
      when,
      if (profile.upiId.trim().isNotEmpty)
        'You can pay by UPI to ${profile.upiId.trim()}.',
      '',
      'Thank you,',
      profile.businessName,
    ].join('\n');
  }

  /// [phone] as digits with country code, or null if it can't be dialled.
  /// Numbers without a country code are taken as Indian.
  static String? internationalNumber(String phone) {
    final digits =
        phone.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
    if (digits.length == 10) return '91$digits';
    return digits.length >= 11 && digits.length <= 15 ? digits : null;
  }

  static Uri? whatsApp(String phone, String message) {
    final number = internationalNumber(phone);
    if (number == null) return null;
    return Uri.https('wa.me', '/$number', {'text': message});
  }

  static Uri? sms(String phone, String message) {
    final number = internationalNumber(phone);
    if (number == null) return null;
    return Uri(
      scheme: 'sms',
      path: '+$number',
      query: 'body=${Uri.encodeComponent(message)}',
    );
  }
}
