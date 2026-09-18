import '../../shared_client/local_storage_manager/local_storage_manager.dart';
import '../data_models/recent_search_data_model.dart';

/// The handful of keywords this device has searched for (REQ102_104).
///
/// A repository is the only layer that talks to the shared clients. This one
/// talks to exactly one of them - [LocalStorageManager] - and **never**
/// [APIManager]: what a tourist typed into the search box is theirs, it is of
/// no use to anyone else, and sending it to Supabase would turn a convenience
/// into a record of someone's movements. The same reasoning as
/// `TutorialRepository`, which is the other local-only repository here.
///
/// Reads are synchronous because `SharedPreferences` is already in memory by
/// the time any View exists (`LocalStorageManager.initialise()` runs in
/// `main()`), so the search bar never waits on a Future to draw its history.
/// Writes are async because the flush to disk is.
class SearchHistoryRepository {
  SearchHistoryRepository();

  final LocalStorageManager storage = LocalStorageManager();

  /// Most recent first. Empty when nothing has been searched yet, and also
  /// when the stored record cannot be read - a device with unreadable history
  /// is a device with no history, not an error the tourist should see.
  List<String> read() {
    final List<String> terms = <String>[];
    for (final Map<String, dynamic> json in storage.readJsonList(_key)) {
      final RecentSearchDataModel? entry = RecentSearchDataModel.fromJson(json);
      if (entry != null) terms.add(entry.term);
    }
    return List<String>.unmodifiable(terms);
  }

  /// Replaces the stored list with [terms], most recent first.
  ///
  /// The whole list every time rather than an append: it is five short strings,
  /// and the alternative is a read-modify-write race between the search box and
  /// whatever else might one day record a term.
  Future<void> write(List<String> terms) => storage.writeJsonList(
    _key,
    terms
        .map((String term) => RecentSearchDataModel(term: term).toJson())
        .toList(growable: false),
  );

  /// A15-1 - the tourist cleared their history. Removes the key rather than
  /// writing an empty list, so nothing about it is left on the device.
  Future<void> clear() => storage.remove(_key);

  static const String _key = LocalStorageManager.keyRecentSearches;
}
