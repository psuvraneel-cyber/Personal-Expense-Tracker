import 'package:pet/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight, privacy-preserving diagnostics tracker for the financial
/// ingestion pipeline.
///
/// Tracks aggregate health counters and recent observation lifecycles WITHOUT
/// storing or logging sensitive financial content, PII, full SMS text, or account numbers.
class IngestionDiagnostics {
  static final IngestionDiagnostics _instance = IngestionDiagnostics._internal();
  factory IngestionDiagnostics() => _instance;
  IngestionDiagnostics._internal();

  static IngestionDiagnostics get instance => _instance;

  static const String _prefPrefix = 'pet_diag_ingest_';

  // Aggregate counters
  int observationsReceived = 0;
  int observationsParsed = 0;
  int autoAccepted = 0;
  int reviewRequired = 0;
  int rejections = 0;
  int duplicatesCollapsed = 0;
  int crossSourceMerged = 0;
  int promotionFailures = 0;
  int billEvents = 0;
  int balanceObservations = 0;
  int backgroundFailures = 0;

  // Ring buffer of recent event records (capped at 50)
  final List<DiagnosticEventEntry> _recentEvents = [];

  List<DiagnosticEventEntry> get recentEvents => List.unmodifiable(_recentEvents);

  /// Load persisted counts from SharedPreferences
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      observationsReceived = prefs.getInt('${_prefPrefix}received') ?? 0;
      observationsParsed = prefs.getInt('${_prefPrefix}parsed') ?? 0;
      autoAccepted = prefs.getInt('${_prefPrefix}autoAccepted') ?? 0;
      reviewRequired = prefs.getInt('${_prefPrefix}reviewRequired') ?? 0;
      rejections = prefs.getInt('${_prefPrefix}rejections') ?? 0;
      duplicatesCollapsed = prefs.getInt('${_prefPrefix}duplicates') ?? 0;
      crossSourceMerged = prefs.getInt('${_prefPrefix}crossSource') ?? 0;
      promotionFailures = prefs.getInt('${_prefPrefix}promotionFailures') ?? 0;
      billEvents = prefs.getInt('${_prefPrefix}billEvents') ?? 0;
      balanceObservations = prefs.getInt('${_prefPrefix}balanceObs') ?? 0;
      backgroundFailures = prefs.getInt('${_prefPrefix}bgFailures') ?? 0;
    } catch (e) {
      AppLogger.debug('[IngestionDiagnostics] Error loading metrics: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_prefPrefix}received', observationsReceived);
      await prefs.setInt('${_prefPrefix}parsed', observationsParsed);
      await prefs.setInt('${_prefPrefix}autoAccepted', autoAccepted);
      await prefs.setInt('${_prefPrefix}reviewRequired', reviewRequired);
      await prefs.setInt('${_prefPrefix}rejections', rejections);
      await prefs.setInt('${_prefPrefix}duplicates', duplicatesCollapsed);
      await prefs.setInt('${_prefPrefix}crossSource', crossSourceMerged);
      await prefs.setInt('${_prefPrefix}promotionFailures', promotionFailures);
      await prefs.setInt('${_prefPrefix}billEvents', billEvents);
      await prefs.setInt('${_prefPrefix}balanceObs', balanceObservations);
      await prefs.setInt('${_prefPrefix}bgFailures', backgroundFailures);
    } catch (e) {
      AppLogger.debug('[IngestionDiagnostics] Error saving metrics: $e');
    }
  }

  void recordReceived() {
    observationsReceived++;
    _save();
  }

  void recordParsed() {
    observationsParsed++;
    _save();
  }

  void recordAutoAccepted() {
    autoAccepted++;
    _save();
  }

  void recordReviewRequired() {
    reviewRequired++;
    _save();
  }

  void recordRejection() {
    rejections++;
    _save();
  }

  void recordDuplicate() {
    duplicatesCollapsed++;
    _save();
  }

  void recordCrossSourceMerge() {
    crossSourceMerged++;
    _save();
  }

  void recordPromotionFailure() {
    promotionFailures++;
    _save();
  }

  void recordBillEvent() {
    billEvents++;
    _save();
  }

  void recordBalanceObservation() {
    balanceObservations++;
    _save();
  }

  void recordBackgroundFailure() {
    backgroundFailures++;
    _save();
  }

  /// Adds a privacy-safe diagnostic record to the ring buffer.
  void recordEvent({
    required String source,
    required String state,
    required double confidence,
    String? bank,
    String? merchant,
    String? decision,
    String? reason,
    String? transactionId,
  }) {
    final entry = DiagnosticEventEntry(
      timestamp: DateTime.now(),
      source: source,
      state: state,
      confidence: confidence,
      bank: bank,
      maskedMerchant: _maskMerchant(merchant),
      decision: decision,
      reason: reason,
      transactionId: transactionId,
    );

    if (_recentEvents.length >= 50) {
      _recentEvents.removeAt(0);
    }
    _recentEvents.add(entry);
  }

  /// Masks personal merchant details or PII, preserving well-known commercial brand names.
  static String _maskMerchant(String? merchant) {
    if (merchant == null || merchant.isEmpty || merchant == 'Unknown') {
      return 'Unknown';
    }
    // If it looks like a person's name or phone number, mask it
    if (RegExp(r'^\d+$').hasMatch(merchant)) {
      return 'Number(masked)';
    }
    return merchant;
  }

  /// Summary snapshot for debug sheets or support diagnostics
  Map<String, dynamic> getSummary() {
    return {
      'observationsReceived': observationsReceived,
      'observationsParsed': observationsParsed,
      'autoAccepted': autoAccepted,
      'reviewRequired': reviewRequired,
      'rejections': rejections,
      'duplicatesCollapsed': duplicatesCollapsed,
      'crossSourceMerged': crossSourceMerged,
      'promotionFailures': promotionFailures,
      'billEvents': billEvents,
      'balanceObservations': balanceObservations,
      'backgroundFailures': backgroundFailures,
      'recentEventsCount': _recentEvents.length,
      'recentEvents': _recentEvents.map((e) => e.toMap()).toList(),
    };
  }

  void reset() {
    observationsReceived = 0;
    observationsParsed = 0;
    autoAccepted = 0;
    reviewRequired = 0;
    rejections = 0;
    duplicatesCollapsed = 0;
    crossSourceMerged = 0;
    promotionFailures = 0;
    billEvents = 0;
    balanceObservations = 0;
    backgroundFailures = 0;
    _recentEvents.clear();
    _save();
  }
}

/// A privacy-safe diagnostic event entry representing an observation lifecycle step.
class DiagnosticEventEntry {
  final DateTime timestamp;
  final String source;
  final String state;
  final double confidence;
  final String? bank;
  final String? maskedMerchant;
  final String? decision;
  final String? reason;
  final String? transactionId;

  DiagnosticEventEntry({
    required this.timestamp,
    required this.source,
    required this.state,
    required this.confidence,
    this.bank,
    this.maskedMerchant,
    this.decision,
    this.reason,
    this.transactionId,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        'state': state,
        'confidence': confidence,
        'bank': bank,
        'merchant': maskedMerchant,
        'decision': decision,
        'reason': reason,
        'transactionId': transactionId,
      };
}
