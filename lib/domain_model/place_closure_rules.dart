/// Pure read-time availability rules for a place's moderation state.
///
/// A place frozen by a TEMPORARY closure (`status='frozen'` with a
/// `closed_until` timestamp) becomes available again once that timestamp
/// passes. These helpers decide that without any I/O, so the three read
/// sites that gate "is this place visible" (map occurrences for restaurants
/// and landmarks, and the restaurant discovery summaries) all treat a
/// frozen-but-expired place the same way - and agree on which ones should be
/// auto-reactivated on read.
///
/// Deliberately does NOT decide the empty/legacy-status behaviour - callers
/// keep their existing conventions there (e.g. the restaurant map read treats
/// a blank `status` as visible because scraped rows never set it).
class PlaceClosureRules {
  PlaceClosureRules._();

  /// Whether a place with moderation [status] should currently be shown
  /// because of its closure state: it is 'available', or it is 'frozen' by a
  /// temporary closure whose `closed_until` has already passed.
  ///
  /// Callers OR this with their own legacy rule for blank/unknown statuses.
  static bool isEffectivelyAvailable({
    String? status,
    DateTime? closedUntil,
    DateTime? now,
  }) {
    final String value = status?.trim().toLowerCase() ?? '';
    if (value == 'available') return true;
    if (value != 'frozen' || closedUntil == null) return false;
    return !closedUntil.isAfter(now ?? DateTime.now());
  }

  /// Whether a place is frozen by a temporary closure whose `closed_until`
  /// has passed - i.e. it should be shown again AND persisted back to
  /// 'available' (the read-time auto-reactivation write).
  static bool needsReactivation({
    String? status,
    DateTime? closedUntil,
    DateTime? now,
  }) {
    final String value = status?.trim().toLowerCase() ?? '';
    if (value != 'frozen' || closedUntil == null) return false;
    return !closedUntil.isAfter(now ?? DateTime.now());
  }
}
