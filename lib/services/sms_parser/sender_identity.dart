/// Parses Indian commercial SMS sender IDs.
///
/// Current TRAI headers look like `JK-BOBSMS-S`: a two-letter operator/circle
/// code, the registered header, and a category suffix — `S` service,
/// `T` transactional, `G` government, `P` promotional. The first two letters
/// say nothing about the message type, so `VK-BOBSMS-S` is a bank service
/// message even though `VK` was once read as "promotional".
library;

class SenderIdentity {
  SenderIdentity._();

  static final RegExp _header = RegExp(
    r'^[A-Z]{2}-([A-Z0-9]{3,9})(?:-([STGP]))?$',
  );

  /// Header tokens registered by banks and payments banks.
  static const List<String> _bankHeaderTokens = [
    'HDFC',
    'ICICI',
    'AXIS',
    'KOTAK',
    'SBI',
    'BOB',
    'BARODA',
    'PNB',
    'CANBNK',
    'CANARA',
    'UNIONB',
    'UBOI',
    'IDFC',
    'YESB',
    'INDUS',
    'INDBNK',
    'IOB',
    'UCOBK',
    'CENTBK',
    'BOIIND',
    'FEDBNK',
    'RBLBNK',
    'IDBI',
    'AUBANK',
    'SCBANK',
    'CITI',
    'HSBC',
    'DBSBNK',
    'BANDHN',
    'KARBNK',
    'SIBSMS',
    'JKBANK',
    'PYTMBK',
    'AIRBNK',
    'JIOPBS',
    'EQUTAS',
    'UJJIVN',
  ];

  /// Whether [sender] is a bank's service or transactional header
  /// (`*-S` / `*-T`, or a legacy header without a suffix).
  static bool isBankServiceSender(String sender) {
    final match = _header.firstMatch(sender.trim().toUpperCase());
    if (match == null) return false;
    final category = match.group(2);
    if (category != null && category != 'S' && category != 'T') return false;
    final header = match.group(1)!;
    return _bankHeaderTokens.any(header.contains);
  }
}
