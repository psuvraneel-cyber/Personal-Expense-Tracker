/// Production-grade normalizer for merchant names in Indian financial messages.
///
/// Cleans raw extracted transaction tokens (strips UPI handles, POS prefixes,
/// technical artifacts) and maps commercial entities to their canonical brand names.
class MerchantNormalizer {
  MerchantNormalizer._();

  // ═══════════════════════════════════════════════════════════════════
  //  CANONICAL MERCHANT MAPPING (Categorized)
  // ═══════════════════════════════════════════════════════════════════

  static final Map<RegExp, String> _brandRules = {
    // ── Food Delivery & Dining ───────────────────────────────────────
    RegExp(r'\bswiggy\b', caseSensitive: false): 'Swiggy',
    RegExp(r'\bzomato\b', caseSensitive: false): 'Zomato',
    RegExp(r'\beatclub\b|\bbox8\b|\bmojo pizza\b', caseSensitive: false):
        'EatClub',
    RegExp(r"\bdomino'?s(?:\s*pizza)?\b|\bjubilant\b", caseSensitive: false):
        "Domino's Pizza",
    RegExp(r"\bpizza\s*hut\b", caseSensitive: false): 'Pizza Hut',
    RegExp(r"\bmcdonald'?s\b|\bhardcastle\b", caseSensitive: false):
        "McDonald's",
    RegExp(r'\bkfc\b|\bdevyani\b', caseSensitive: false): 'KFC',
    RegExp(r'\bburger\s*king\b', caseSensitive: false): 'Burger King',
    RegExp(r'\bstarbucks\b|\btata\s*starbucks\b', caseSensitive: false):
        'Starbucks',
    RegExp(r'\bchai\s*point\b', caseSensitive: false): 'Chai Point',
    RegExp(r'\bchaayos\b', caseSensitive: false): 'Chaayos',
    RegExp(r'\bsubway\b', caseSensitive: false): 'Subway',
    RegExp(r'\bhaldiram\b', caseSensitive: false): "Haldiram's",

    // ── Grocery & Quick Commerce ─────────────────────────────────────
    RegExp(r'\bblinkit\b|\bgrofers\b', caseSensitive: false): 'Blinkit',
    RegExp(r'\bzepto\b', caseSensitive: false): 'Zepto',
    RegExp(r'\binstamart\b', caseSensitive: false): 'Instamart',
    RegExp(r'\bbigbasket\b|\bbbnow\b', caseSensitive: false): 'BigBasket',
    RegExp(r'\bdmart\b|\bavenue\s*supermarts\b', caseSensitive: false): 'DMart',
    RegExp(r'\bdunzo\b', caseSensitive: false): 'Dunzo',
    RegExp(r"\bnature'?s\s*basket\b", caseSensitive: false): "Nature's Basket",
    RegExp(r'\bjiomart\b', caseSensitive: false): 'JioMart',

    // ── Cab & Mobility ───────────────────────────────────────────────
    RegExp(r'\buber\b', caseSensitive: false): 'Uber',
    RegExp(r'\bolacabs\b|\bola\b|\bani\s*technologies\b', caseSensitive: false):
        'Ola',
    RegExp(r'\brapido\b|\broppen\b', caseSensitive: false): 'Rapido',
    RegExp(r'\bnamma\s*yatri\b', caseSensitive: false): 'Namma Yatri',
    RegExp(r'\bblusmart\b', caseSensitive: false): 'BluSmart',

    // ── Travel & Ticketing ───────────────────────────────────────────
    RegExp(r'\bmakemytrip\b|\bmmt\b', caseSensitive: false): 'MakeMyTrip',
    RegExp(r'\bgoibibo\b', caseSensitive: false): 'Goibibo',
    RegExp(r'\bcleartrip\b', caseSensitive: false): 'Cleartrip',
    RegExp(r'\byatra\b', caseSensitive: false): 'Yatra',
    RegExp(r'\birctc\b', caseSensitive: false): 'IRCTC',
    RegExp(r'\bredbus\b', caseSensitive: false): 'RedBus',
    RegExp(r'\beasemytrip\b', caseSensitive: false): 'EaseMyTrip',
    RegExp(r'\bindigo\b|\binterglobe\b', caseSensitive: false): 'IndiGo',
    RegExp(r'\bair\s*india\b', caseSensitive: false): 'Air India',
    RegExp(r'\bakasa\b', caseSensitive: false): 'Akasa Air',
    RegExp(r'\bvistara\b', caseSensitive: false): 'Vistara',

    // ── E-Commerce & Retail ──────────────────────────────────────────
    RegExp(r'\bamazon\b|\bamzn\b', caseSensitive: false): 'Amazon',
    RegExp(r'\bflipkart\b', caseSensitive: false): 'Flipkart',
    RegExp(r'\bmyntra\b', caseSensitive: false): 'Myntra',
    RegExp(r'\bmeesho\b', caseSensitive: false): 'Meesho',
    RegExp(r'\bajio\b', caseSensitive: false): 'Ajio',
    RegExp(r'\bnykaa\b', caseSensitive: false): 'Nykaa',
    RegExp(r'\btata\s*cliq\b', caseSensitive: false): 'Tata CLiQ',
    RegExp(r'\breliance\s*digital\b', caseSensitive: false): 'Reliance Digital',
    RegExp(r'\bcroma\b|\binfiniti\s*retail\b', caseSensitive: false): 'Croma',

    // ── Pharmacy & Healthcare ────────────────────────────────────────
    RegExp(r'\bapollo\s*(?:pharmacy|hospital)?\b', caseSensitive: false):
        'Apollo',
    RegExp(r'\bnetmeds\b', caseSensitive: false): 'Netmeds',
    RegExp(r'\btata\s*1mg\b|\b1mg\b', caseSensitive: false): 'Tata 1mg',
    RegExp(r'\bpharmeasy\b', caseSensitive: false): 'PharmEasy',
    RegExp(r'\bmedplus\b', caseSensitive: false): 'MedPlus',

    // ── Telecom & Broadband ──────────────────────────────────────────
    RegExp(r'\bjio\b|\breliance\s*jio\b', caseSensitive: false): 'Jio',
    RegExp(r'\bairtel\b|\bbharti\s*airtel\b', caseSensitive: false): 'Airtel',
    RegExp(r'\bvodafone\b|\bidea\b|\bvi\b', caseSensitive: false): 'Vi',
    RegExp(r'\bbsnl\b', caseSensitive: false): 'BSNL',
    RegExp(r'\bact\s*(?:fibernet)?\b', caseSensitive: false): 'ACT Fibernet',
    RegExp(r'\btata\s*play\b|\btata\s*sky\b', caseSensitive: false):
        'Tata Play',

    // ── Utilities & Fuel ─────────────────────────────────────────────
    RegExp(r'\bbescom\b', caseSensitive: false): 'BESCOM',
    RegExp(r'\btata\s*power\b', caseSensitive: false): 'Tata Power',
    RegExp(r'\badani\s*(?:electricity|power)?\b', caseSensitive: false):
        'Adani Electricity',
    RegExp(r'\bindraprastha\s*gas\b|\bigl\b', caseSensitive: false): 'IGL',
    RegExp(r'\bmahanagar\s*gas\b|\bmgl\b', caseSensitive: false): 'MGL',
    RegExp(r'\bindane\b|\biocl\b|\bindian\s*oil\b', caseSensitive: false):
        'Indian Oil',
    RegExp(r'\bhpcl\b|\bhp\s*petrol\b|\bhp\s*gas\b', caseSensitive: false):
        'HPCL',
    RegExp(r'\bbpcl\b|\bbharat\s*petroleum\b', caseSensitive: false): 'BPCL',

    // ── Entertainment & Streaming ────────────────────────────────────
    RegExp(r'\bnetflix\b', caseSensitive: false): 'Netflix',
    RegExp(r'\bprime\s*video\b|\bamazon\s*prime\b', caseSensitive: false):
        'Amazon Prime',
    RegExp(r'\bhotstar\b|\bdisney\b', caseSensitive: false): 'Disney+ Hotstar',
    RegExp(r'\bspotify\b', caseSensitive: false): 'Spotify',
    RegExp(r'\byoutube\b', caseSensitive: false): 'YouTube',
    RegExp(r'\bbookmyshow\b|\bbms\b', caseSensitive: false): 'BookMyShow',
    RegExp(r'\bsonyliv\b', caseSensitive: false): 'SonyLIV',
    RegExp(r'\bzee5\b', caseSensitive: false): 'Zee5',
    RegExp(r'\bjiocinema\b', caseSensitive: false): 'JioCinema',

    // ── Wallets & Fintech ────────────────────────────────────────────
    RegExp(r'\bphonepe\b', caseSensitive: false): 'PhonePe',
    RegExp(r'\bgpay\b|\bgoogle\s*pay\b', caseSensitive: false): 'Google Pay',
    RegExp(r'\bpaytm\b', caseSensitive: false): 'Paytm',
    RegExp(r'\bcred\b', caseSensitive: false): 'CRED',
    RegExp(r'\bnavi\b', caseSensitive: false): 'Navi',
    RegExp(r'\bmobikwik\b', caseSensitive: false): 'MobiKwik',
    RegExp(r'\bfreecharge\b', caseSensitive: false): 'Freecharge',
    RegExp(r'\bslice\b', caseSensitive: false): 'Slice',
    RegExp(r'\bjupiter\b', caseSensitive: false): 'Jupiter',
    RegExp(r'\bfi\s*money\b', caseSensitive: false): 'Fi Money',

    // ── Subscriptions & Tech ─────────────────────────────────────────
    RegExp(r'\bgoogle\s*(?:one|cloud|play)?\b', caseSensitive: false): 'Google',
    RegExp(r'\bapple\b|\bicloud\b|\bitunes\b', caseSensitive: false): 'Apple',
    RegExp(r'\bchatgpt\b|\bopenai\b', caseSensitive: false): 'ChatGPT',
    RegExp(r'\bmicrosoft\b', caseSensitive: false): 'Microsoft',
  };

  // ═══════════════════════════════════════════════════════════════════
  //  PUBLIC NORMALIZATION API
  // ═══════════════════════════════════════════════════════════════════

  /// Normalizes a raw extracted merchant string into a clean, human-readable name.
  static String normalize(String merchant) {
    var cleaned = merchant.trim();
    if (cleaned.isEmpty) return 'Unknown';

    // 1. Strip common technical prefixes
    cleaned = cleaned
        .replaceAll(
          RegExp(
              r'^(?:UPI[-/]?|POS\s*[-/]?|VPA\s*[-/]?|INFO:\s*|TO\s+|AT\s+|PAYMENT\s+TO\s+)',
              caseSensitive: false),
          '',
        )
        .trim();

    // 2. Check canonical brand dictionary
    for (final entry in _brandRules.entries) {
      if (entry.key.hasMatch(cleaned)) {
        return entry.value;
      }
    }

    // 3. Handle raw UPI addresses: e.g. "sharma.kirana@okaxis" -> "Sharma Kirana"
    if (cleaned.contains('@')) {
      final handlePart = cleaned.split('@').first;
      // If handle is a 10-digit phone number, keep it as merchant identifier
      if (RegExp(r'^\d{10}$').hasMatch(handlePart)) {
        return cleaned;
      }
      cleaned = handlePart
          .replaceAll('.', ' ')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .trim();
    }

    // 4. Strip technical trailing suffixes
    cleaned = cleaned
        .replaceAll(
          RegExp(
              r'\s+(?:pv?t\.?\s*ltd\.?|limited|ltd\.?|india|services|store|retail|online)$',
              caseSensitive: false),
          '',
        )
        .trim();

    // 5. Casing cleanup
    if (cleaned.isEmpty) return 'Unknown';
    if (cleaned.length <= 3) return cleaned.toUpperCase();

    // Title Case
    return cleaned
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          if (word.length == 1) return word.toUpperCase();
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ')
        .trim();
  }
}
