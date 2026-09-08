class SpendPause {
  final bool enabled;

  /// When the pause auto-expires. Null means indefinite.
  final DateTime? until;

  /// Stable category IDs that are blocked during the pause.
  final List<String> blockedCategoryIds;

  SpendPause({
    required this.enabled,
    this.until,
    List<String>? blockedCategoryIds,
    List<String>? blockedCategories,
  }) : blockedCategoryIds = blockedCategoryIds ?? blockedCategories ?? const [];

  /// Backward-compatible alias for [blockedCategoryIds].
  List<String> get blockedCategories => blockedCategoryIds;

  /// Returns true if the pause is enabled and has not yet expired.
  bool get isActive {
    if (!enabled) return false;
    if (until == null) return true;
    return DateTime.now().isBefore(until!);
  }

  /// Remaining duration until expiration. Returns Duration.zero if expired or disabled.
  Duration get remainingDuration {
    if (!isActive || until == null) return Duration.zero;
    final diff = until!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Checks if a category is blocked by its stable unique ID.
  bool isCategoryBlocked(String categoryId) {
    if (!isActive) return false;
    return blockedCategoryIds.contains(categoryId);
  }
}
