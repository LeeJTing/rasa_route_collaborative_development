import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed, validated access to `.env`.
///
/// `.env` is git-ignored. `.env.example` is committed and lists every key the
/// app needs - keep the two in sync whenever you add a variable.
///
/// RULE: nothing outside this class reads configuration. Adding a getter here
/// is what makes a missing key fail loudly at start-up instead of silently
/// producing `null` deep inside a repository.
/// [load] fills [_values] from the local asset and lets `--dart-define`
/// override individual values for CI/release builds.
abstract final class Env {
  const Env._();

  static const String _fileName = '.env';

  static final Map<String, String> _values = <String, String>{};

  static bool _loaded = false;

  /// Loads the git-ignored local file. Non-empty `--dart-define` values take
  /// precedence, which keeps release configuration outside the source tree.
  static Future<void> load({String fileName = _fileName}) async {
    await dotenv.load(fileName: fileName, isOptional: true);
    _values
      ..clear()
      ..addAll(dotenv.env)
      ..addAll(_compileTimeOverrides);
    _loaded = true;
  }

  /// Throws [EnvException] when a required key is missing, so the app fails at
  /// start-up rather than at the first network call.
  static void validate() {
    const List<String> required = <String>[
      _keySupabaseUrl,
      _keySupabasePublishableKey,
      _keyGeminiApiKey,
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

  static const String _keySupabaseUrl = 'SUPABASE_URL';
  static const String _keySupabasePublishableKey = 'SUPABASE_PUBLISHABLE_KEY';
  static const String _keyGeminiApiKey = 'GEMINI_API_KEY';
  static const String _keyGeminiModel = 'GEMINI_MODEL';
  static const String _keyGeminiApiKeyLandmark = 'GEMINI_API_KEY_LANDMARK';
  static const String _keyGeminiModelLandmark = 'GEMINI_MODEL_LANDMARK';
  static const String _keyGeminiFallbackModels = 'GEMINI_FALLBACK_MODELS';
  static const String _keyOsmBaseUrl = 'OSM_BASE_URL';
  static const String _keyOsmTileUrl = 'OSM_TILE_URL';
  static const String _keyApiTimeoutSeconds = 'API_TIMEOUT_SECONDS';
  static const String _keyAppEnv = 'APP_ENV';
  static const String _keyVerboseLogging = 'ENABLE_VERBOSE_LOGGING';
  static const String _keyLocationPollSeconds = 'LOCATION_POLL_SECONDS';
  static const String _keyRestaurantSyncMinutes = 'RESTAURANT_SYNC_MINUTES';

  static Map<String, String> get _compileTimeOverrides {
    const Map<String, String> values = <String, String>{
      _keySupabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      _keySupabasePublishableKey: String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      _keyGeminiApiKey: String.fromEnvironment('GEMINI_API_KEY'),
      _keyGeminiModel: String.fromEnvironment('GEMINI_MODEL'),
      _keyGeminiApiKeyLandmark: String.fromEnvironment(
        'GEMINI_API_KEY_LANDMARK',
      ),
      _keyGeminiModelLandmark: String.fromEnvironment('GEMINI_MODEL_LANDMARK'),
      _keyGeminiFallbackModels: String.fromEnvironment(
        'GEMINI_FALLBACK_MODELS',
      ),
      _keyOsmBaseUrl: String.fromEnvironment('OSM_BASE_URL'),
      _keyOsmTileUrl: String.fromEnvironment('OSM_TILE_URL'),
      _keyApiTimeoutSeconds: String.fromEnvironment('API_TIMEOUT_SECONDS'),
      _keyAppEnv: String.fromEnvironment('APP_ENV'),
      _keyVerboseLogging: String.fromEnvironment('ENABLE_VERBOSE_LOGGING'),
      _keyLocationPollSeconds: String.fromEnvironment('LOCATION_POLL_SECONDS'),
      _keyRestaurantSyncMinutes: String.fromEnvironment(
        'RESTAURANT_SYNC_MINUTES',
      ),
    };
    return <String, String>{
      for (final MapEntry<String, String> entry in values.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  static String get supabaseUrl => _read(_keySupabaseUrl);

  static String get supabasePublishableKey => _read(_keySupabasePublishableKey);

  static String get geminiApiKey => _read(_keyGeminiApiKey);

  static String get geminiModel =>
      _read(_keyGeminiModel, fallback: 'gemini-3.5-flash-lite');

  /// Optional UC500-specific key; falls back to [geminiApiKey] when unset.
  static String get geminiApiKeyLandmark =>
      _read(_keyGeminiApiKeyLandmark, fallback: geminiApiKey);

  /// Optional UC500-specific model; falls back to [geminiModel] when unset.
  static String get geminiModelLandmark =>
      _read(_keyGeminiModelLandmark, fallback: geminiModel);

  /// Ordered models to try when the primary Gemini model is temporarily
  /// unavailable (HTTP 429 rate-limited / 5xx high demand, e.g. 503).
  /// Comma-separated in `.env` (`GEMINI_FALLBACK_MODELS`); defaults to three
  /// common Gemini models when unset. See `GeminiService._generate`.
  static List<String> get geminiFallbackModels {
    const List<String> defaults = <String>[
      'gemini-3.6-flash',
      'gemini-3.5-flash',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
    ];
    final String raw = _read(_keyGeminiFallbackModels);
    if (raw.isEmpty) return defaults;
    final List<String> parsed = raw
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    return parsed.isEmpty ? defaults : parsed;
  }

  static String get osmBaseUrl =>
      _read(_keyOsmBaseUrl, fallback: 'https://overpass-api.de/api');

  static String get osmTileUrl => _read(
    _keyOsmTileUrl,
    fallback: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static Duration get apiTimeout =>
      Duration(seconds: _readInt(_keyApiTimeoutSeconds, 120));

  static Duration get locationPollInterval =>
      Duration(seconds: _readInt(_keyLocationPollSeconds, 30));

  static Duration get restaurantSyncInterval =>
      Duration(minutes: _readInt(_keyRestaurantSyncMinutes, 15));

  /// One of `dev`, `staging`, `prod`.
  static String get appEnv => _read(_keyAppEnv, fallback: 'dev');

  static bool get isProduction => appEnv == 'prod';

  static bool get verboseLogging =>
      _readBool(_keyVerboseLogging, fallback: !isProduction);

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
