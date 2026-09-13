/// One remembered search term, as it is written to device storage (REQ102_104).
///
/// A data model owns the serialisation. This one has no backend behind it:
/// search history never reaches Supabase, so the "wire shape" here is the JSON
/// that goes into [LocalStorageManager] and comes back out of it, and the
/// object it mirrors is the one this app wrote on the last run.
///
/// A record rather than a bare string because the stored value has to survive
/// a future field - a timestamp, a result count - without the old entries
/// becoming unreadable. A list of bare strings could not have been extended
/// without discarding what a tourist's device already held.
class RecentSearchDataModel {
  const RecentSearchDataModel({required this.term});

  /// Returns null for a record with nothing usable in it, so one corrupt entry
  /// costs that entry rather than the whole history.
  static RecentSearchDataModel? fromJson(Map<String, dynamic> json) {
    final String term = (json['term'] ?? '').toString().trim();
    if (term.isEmpty) return null;
    return RecentSearchDataModel(term: term);
  }

  final String term;

  Map<String, dynamic> toJson() => <String, dynamic>{'term': term};
}
