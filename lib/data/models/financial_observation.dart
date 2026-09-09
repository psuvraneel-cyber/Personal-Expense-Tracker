import 'dart:convert';
import 'package:crypto/crypto.dart';

/// The origin of an incoming external financial observation.
enum FinancialObservationSource {
  sms,
  notification,
  reconciliation;

  String toJson() => name;

  static FinancialObservationSource fromJson(String? value) {
    if (value == 'notification') return FinancialObservationSource.notification;
    if (value == 'reconciliation')
      return FinancialObservationSource.reconciliation;
    return FinancialObservationSource.sms;
  }
}

/// Lifecycle states of a financial observation within the ingestion pipeline.
enum FinancialObservationState {
  received,
  normalized,
  parsed,
  deduplicated,
  accepted,
  uncertain,
  rejected,
  promoted,
  linked,
  ignored,
  failed;

  String toJson() => name;

  static FinancialObservationState fromJson(String? value) {
    return FinancialObservationState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FinancialObservationState.received,
    );
  }
}

/// Ingestion decision produced by the classification and evidence engine.
enum IngestionDecision {
  autoAccept,
  reviewRequired,
  reject,
  routeToBill,
  routeToBalance;

  String toJson() => name;

  static IngestionDecision fromJson(String? value) {
    return IngestionDecision.values.firstWhere(
      (e) => e.name == value,
      orElse: () => IngestionDecision.reviewRequired,
    );
  }
}

/// Canonical internal representation of an incoming financial event
/// observed via SMS, push notification, or inbox reconciliation.
class FinancialObservation {
  final String observationId;
  final FinancialObservationSource source;
  final String sourceIdentifier; // Originating SMS address or app package name
  final String? sender;
  final String? packageName;
  final String? title;
  final String body;
  final String normalizedText;
  final DateTime receivedAt;
  final DateTime sourceTimestamp;
  final String? accountHint;
  final int schemaVersion;
  final String observationHash;
  final String? sourceFingerprint;
  final FinancialObservationState state;
  final String? stateReason;
  final double confidence;
  final String? canonicalTransactionId;
  final String? relatedBillId;
  final double? observedBalance;
  final String? accountTail;
  final String? rawPayload;
  final Map<String, dynamic> metadata;

  FinancialObservation({
    required this.observationId,
    required this.source,
    required this.sourceIdentifier,
    this.sender,
    this.packageName,
    this.title,
    required this.body,
    required this.normalizedText,
    required this.receivedAt,
    required this.sourceTimestamp,
    this.accountHint,
    this.schemaVersion = 1,
    required this.observationHash,
    this.sourceFingerprint,
    this.state = FinancialObservationState.received,
    this.stateReason,
    this.confidence = 0.0,
    this.canonicalTransactionId,
    this.relatedBillId,
    this.observedBalance,
    this.accountTail,
    this.rawPayload,
    this.metadata = const {},
  });

  /// Compute a SHA-256 hash from normalized text and timestamp for raw dedup.
  static String generateHash(String text, DateTime timestamp) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final input = '$normalized|${timestamp.millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Create a canonical normalized text representation from title and body.
  /// Avoids duplication if title and body are identical.
  static String buildNormalizedText({String? title, required String body}) {
    final cleanBody = body.trim();
    final cleanTitle = title?.trim() ?? '';
    if (cleanTitle.isEmpty || cleanBody.contains(cleanTitle)) {
      return cleanBody;
    }
    return '$cleanTitle — $cleanBody';
  }

  Map<String, dynamic> toMap() {
    return {
      'observationId': observationId,
      'source': source.toJson(),
      'sourceIdentifier': sourceIdentifier,
      'sender': sender,
      'packageName': packageName,
      'title': title,
      'body': body,
      'normalizedText': normalizedText,
      'receivedAt': receivedAt.toIso8601String(),
      'sourceTimestamp': sourceTimestamp.toIso8601String(),
      'accountHint': accountHint,
      'schemaVersion': schemaVersion,
      'observationHash': observationHash,
      'sourceFingerprint': sourceFingerprint,
      'state': state.toJson(),
      'stateReason': stateReason,
      'confidence': confidence,
      'canonicalTransactionId': canonicalTransactionId,
      'relatedBillId': relatedBillId,
      'observedBalance': observedBalance,
      'accountTail': accountTail,
      'rawPayload': rawPayload ?? jsonEncode(metadata),
    };
  }

  factory FinancialObservation.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedMeta = {};
    if (map['rawPayload'] != null && map['rawPayload'] is String) {
      try {
        final decoded = jsonDecode(map['rawPayload'] as String);
        if (decoded is Map<String, dynamic>) {
          parsedMeta = decoded;
        }
      } catch (_) {}
    }

    return FinancialObservation(
      observationId: map['observationId'] as String,
      source: FinancialObservationSource.fromJson(map['source'] as String?),
      sourceIdentifier: map['sourceIdentifier'] as String? ?? '',
      sender: map['sender'] as String?,
      packageName: map['packageName'] as String?,
      title: map['title'] as String?,
      body: map['body'] as String? ?? '',
      normalizedText:
          map['normalizedText'] as String? ?? map['body'] as String? ?? '',
      receivedAt: map['receivedAt'] != null
          ? DateTime.parse(map['receivedAt'] as String)
          : DateTime.now(),
      sourceTimestamp: map['sourceTimestamp'] != null
          ? DateTime.parse(map['sourceTimestamp'] as String)
          : DateTime.now(),
      accountHint: map['accountHint'] as String?,
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      observationHash: map['observationHash'] as String,
      sourceFingerprint: map['sourceFingerprint'] as String?,
      state: FinancialObservationState.fromJson(map['state'] as String?),
      stateReason: map['stateReason'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      canonicalTransactionId: map['canonicalTransactionId'] as String?,
      relatedBillId: map['relatedBillId'] as String?,
      observedBalance: (map['observedBalance'] as num?)?.toDouble(),
      accountTail: map['accountTail'] as String?,
      rawPayload: map['rawPayload'] as String?,
      metadata: parsedMeta,
    );
  }

  FinancialObservation copyWith({
    String? observationId,
    FinancialObservationSource? source,
    String? sourceIdentifier,
    String? sender,
    String? packageName,
    String? title,
    String? body,
    String? normalizedText,
    DateTime? receivedAt,
    DateTime? sourceTimestamp,
    String? accountHint,
    int? schemaVersion,
    String? observationHash,
    String? sourceFingerprint,
    FinancialObservationState? state,
    String? stateReason,
    double? confidence,
    String? canonicalTransactionId,
    String? relatedBillId,
    double? observedBalance,
    String? accountTail,
    String? rawPayload,
    Map<String, dynamic>? metadata,
  }) {
    return FinancialObservation(
      observationId: observationId ?? this.observationId,
      source: source ?? this.source,
      sourceIdentifier: sourceIdentifier ?? this.sourceIdentifier,
      sender: sender ?? this.sender,
      packageName: packageName ?? this.packageName,
      title: title ?? this.title,
      body: body ?? this.body,
      normalizedText: normalizedText ?? this.normalizedText,
      receivedAt: receivedAt ?? this.receivedAt,
      sourceTimestamp: sourceTimestamp ?? this.sourceTimestamp,
      accountHint: accountHint ?? this.accountHint,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      observationHash: observationHash ?? this.observationHash,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      state: state ?? this.state,
      stateReason: stateReason ?? this.stateReason,
      confidence: confidence ?? this.confidence,
      canonicalTransactionId:
          canonicalTransactionId ?? this.canonicalTransactionId,
      relatedBillId: relatedBillId ?? this.relatedBillId,
      observedBalance: observedBalance ?? this.observedBalance,
      accountTail: accountTail ?? this.accountTail,
      rawPayload: rawPayload ?? this.rawPayload,
      metadata: metadata ?? this.metadata,
    );
  }
}
