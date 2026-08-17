import 'dart:convert';

/// The single local data source.
///
/// Repositories use this for offline caching and for the handful of values that
/// never leave the device (last map viewport, onboarding flags, auth session).
/// Nothing else in the app may touch device storage directly.
///
/// A singleton: `LocalStorageManager()` always returns the same instance, so
/// every repository shares one cache without anyone passing it around.
///
/// Currently an in-memory map, so nothing survives a restart. Swap the map for
/// a real store without changing the public API.
class LocalStorageManager {
  factory LocalStorageManager() => _instance;

  LocalStorageManager._();

  static final LocalStorageManager _instance = LocalStorageManager._();

  final Map<String, String> _memory = <String, String>{};

  /// Called once from `main()` when a real store needs opening.
  Future<void> initialise() async {}

  // --- Keys ------------------------------------------------------------------

  static const String keyAuthSession = 'auth_session';
  static const String keyTouristProfile = 'tourist_profile';
  static const String keyLastMapViewport = 'last_map_viewport';
  static const String keyLastKnownLocation = 'last_known_location';
  static const String keyFavouriteFoodIds = 'favourite_food_ids';
  static const String keyHasSeenOnboarding = 'has_seen_onboarding';
  static const String keyActiveSwipeSession = 'active_swipe_session';

  /// Suffix appended to a cache key to store its write time.
  static String _stampKey(String key) => '${key}__written_at';

  // --- Primitives ------------------------------------------------------------

  String? readString(String key) => _memory[key];

  Future<void> writeString(String key, String value) async {
    _memory[key] = value;
  }

  bool readBool(String key, {bool fallback = false}) {
    final String? raw = readString(key);
    if (raw == null) return fallback;
    return raw == 'true';
  }

  Future<void> writeBool(String key, bool value) =>
      writeString(key, value.toString());

  List<String> readStringList(String key) {
    final String? raw = readString(key);
    if (raw == null || raw.isEmpty) return const <String>[];
    return raw.split(' ');
  }

  Future<void> writeStringList(String key, List<String> value) =>
      writeString(key, value.join(' '));

  Future<void> remove(String key) async {
    _memory.remove(key);
    _memory.remove(_stampKey(key));
  }

  Future<void> clear() async => _memory.clear();

  // --- JSON ------------------------------------------------------------------

  /// Reads a cached object. Returns null when absent or unparseable.
  Map<String, dynamic>? readJson(String key) {
    final String? raw = readString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// Writes an object and stamps it with the current time.
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    await writeString(key, jsonEncode(value));
    await writeString(_stampKey(key), DateTime.now().toIso8601String());
  }

  List<Map<String, dynamic>> readJsonList(String key) {
    final String? raw = readString(key);
    if (raw == null || raw.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> writeJsonList(
    String key,
    List<Map<String, dynamic>> value,
  ) async {
    await writeString(key, jsonEncode(value));
    await writeString(_stampKey(key), DateTime.now().toIso8601String());
  }

  // --- Freshness -------------------------------------------------------------

  /// When [key] was last written, or null if never.
  DateTime? writtenAt(String key) {
    final String? raw = readString(_stampKey(key));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// `true` when [key] is missing or older than [maxAge].
  ///
  /// This is how a repository chooses between the local and the remote source:
  /// ```dart
  /// if (storage.isStale(key, const Duration(hours: 6))) {
  ///   // fetch through APIManager and cache
  /// }
  /// ```
  bool isStale(String key, Duration maxAge) {
    final DateTime? at = writtenAt(key);
    if (at == null) return true;
    return DateTime.now().difference(at) > maxAge;
  }
}
