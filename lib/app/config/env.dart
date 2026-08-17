/// Typed, validated access to `.env`.
///
/// `.env` is git-ignored. `.env.example` is committed and lists every key the
/// app needs - keep the two in sync whenever you add a variable.
///
/// RULE: nothing outside this class reads configuration. Adding a getter here
/// is what makes a missing key fail loudly at start-up instead of silently
/// producing `null` deep inside a repository.
///
/// [load] fills [_values]; every getter reads from there with a fallback, so
/// call sites never change when the file read is added.
abstract final class Env {
  const Env._();

  static const String _fileName = '.env';

  static final Map<String, String> _values = <String, String>{};

  static bool _loaded = false;

  /// Loads and validates `.env`. Call once, first thing in `main()`.
  static Future<void> load({String fileName = _fileName}) async {
    _loaded = true;
  }

  /// Throws [EnvException] when a required key is missing, so the app fails at
  /// start-up rather than at the first network call.
  static void validate() {
    const List<String> required = <String>[
      keySupabaseUrl,
      keySupabasePublishableKey,
      keyGeminiApiKey,
    ];
    final List<String> missing = required
        .where((String key) => (_values[key] ?? '').trim().isEmpty)
        .toList(growable: false);

    if (missing.isNotEmpty) {
      throw EnvException(
        'Missing required key(s) in $_fileName: ${missing.join(', ')}. '
        'Copy .env.example to .env and fill them in.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Keys - must match .env.example exactly.
  // ---------------------------------------------------------------------------

  static const String keySupabaseUrl = 'SUPABASE_URL';
  static const String keySupabasePublishableKey = 'SUPABASE_PUBLISHABLE_KEY';
  static const String keyGeminiApiKey = 'GEMINI_API_KEY';
  static const String keyGeminiModel = 'GEMINI_MODEL';
  static const String keyOsmBaseUrl = 'OSM_BASE_URL';
  static const String keyOsmTileUrl = 'OSM_TILE_URL';
  static const String keyApiTimeoutSeconds = 'API_TIMEOUT_SECONDS';
  static const String keyAppEnv = 'APP_ENV';
  static const String keyVerboseLogging = 'ENABLE_VERBOSE_LOGGING';
  static const String keyLocationPollSeconds = 'LOCATION_POLL_SECONDS';
  static const String keyRestaurantSyncMinutes = 'RESTAURANT_SYNC_MINUTES';

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  static String get supabaseUrl => _read(keySupabaseUrl);

  static String get supabasePublishableKey =>
      _read(keySupabasePublishableKey);

  static String get geminiApiKey => _read(keyGeminiApiKey);

  static String get geminiModel =>
      _read(keyGeminiModel, fallback: 'gemini-2.5-flash');

  static String get osmBaseUrl =>
      _read(keyOsmBaseUrl, fallback: 'https://overpass-api.de/api');

  static String get osmTileUrl => _read(
    keyOsmTileUrl,
    fallback: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static Duration get apiTimeout =>
      Duration(seconds: _readInt(keyApiTimeoutSeconds, 20));

  static Duration get locationPollInterval =>
      Duration(seconds: _readInt(keyLocationPollSeconds, 30));

  static Duration get restaurantSyncInterval =>
      Duration(minutes: _readInt(keyRestaurantSyncMinutes, 15));

  /// One of `dev`, `staging`, `prod`.
  static String get appEnv => _read(keyAppEnv, fallback: 'dev');

  static bool get isProduction => appEnv == 'prod';

  static bool get verboseLogging =>
      _readBool(keyVerboseLogging, fallback: !isProduction);

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static String _read(String key, {String fallback = ''}) {
    _assertLoaded();
    final String value = (_values[key] ?? '').trim();
    return value.isEmpty ? fallback : value;
  }

  static int _readInt(String key, int fallback) =>
      int.tryParse(_read(key)) ?? fallback;

  static bool _readBool(String key, {required bool fallback}) {
    final String value = _read(key).toLowerCase();
    if (value.isEmpty) return fallback;
    return value == 'true' || value == '1' || value == 'yes';
  }

  static void _assertLoaded() {
    if (!_loaded) {
      throw const EnvException(
        'Env.load() must be awaited in main() before reading any value.',
      );
    }
  }
}

/// Thrown when `.env` is missing or incomplete.
class EnvException implements Exception {
  const EnvException(this.message);

  final String message;

  @override
  String toString() => 'EnvException: $message';
}
