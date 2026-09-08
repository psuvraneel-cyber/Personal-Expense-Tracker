import 'package:flutter/foundation.dart';

/// Immutable identity token representing an authenticated user session.
///
/// Combines the authenticated user's UID and an incrementing session generation counter.
/// Asynchronous callbacks (Firestore snapshots, SQLite sync operations, Future completions)
/// capture this token when dispatched and verify it before mutating application state.
@immutable
class AccountSession {
  final String? uid;
  final int generation;

  const AccountSession({
    required this.uid,
    required this.generation,
  });

  /// An unauthenticated or guest session with generation 0.
  static const AccountSession unauthenticated = AccountSession(
    uid: null,
    generation: 0,
  );

  /// Checks whether this session remains authoritative against the active state.
  bool isValidFor(String? currentUid, int currentGeneration) {
    return uid == currentUid && generation == currentGeneration;
  }

  /// Checks whether this session matches another [AccountSession] instance.
  bool matches(AccountSession other) {
    return uid == other.uid && generation == other.generation;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountSession &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          generation == other.generation;

  @override
  int get hashCode => Object.hash(uid, generation);

  @override
  String toString() => 'AccountSession(uid: $uid, gen: $generation)';
}
