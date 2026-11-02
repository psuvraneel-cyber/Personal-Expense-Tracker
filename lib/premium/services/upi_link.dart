/// UPI "pay" links (NPCI deep-link format), printed as a QR code on invoices.
class UpiLink {
  UpiLink._();

  static final RegExp _vpa = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');

  static bool isValidVpa(String vpa) => _vpa.hasMatch(vpa.trim());

  /// `upi://pay?pa=…&pn=…&am=…&cu=INR&tn=…&tr=…`. The invoice number goes in
  /// the note and the reference, so the payer's app shows what it is for.
  static String build({
    required String vpa,
    required String payeeName,
    required double amount,
    String note = '',
    String reference = '',
  }) {
    final params = <String, String>{
      'pa': vpa.trim(),
      'pn': payeeName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      if (note.isNotEmpty) 'tn': note,
      if (reference.isNotEmpty) 'tr': reference,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'upi://pay?$query';
  }
}
