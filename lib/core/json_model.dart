/// Contract every serialisable model implements.
///
/// Both `lib/model/data_models/` (wire shape - mirrors Supabase columns) and
/// `lib/domain_model/` (what the app reasons about) implement this so the
/// serialisation surface is uniform and testable:
///
/// ```dart
/// final json = model.toJson();
/// expect(LocalFoodDataModel.fromJson(json).toJson(), json);
/// ```
abstract interface class JsonModel {
  /// Serialises this instance to a JSON-safe map.
  ///
  /// Only `String`, `num`, `bool`, `null`, `List` and `Map` may appear in the
  /// output - `DateTime` becomes an ISO-8601 string, enums become their name.
  Map<String, dynamic> toJson();
}

/// Helpers for defensive parsing of Supabase / REST payloads.
///
/// Supabase returns `numeric` as `String` on some drivers, timestamps as ISO
/// strings, and `null` for any nullable column - these helpers absorb that so
/// `fromJson` bodies stay one line per field.
abstract final class JsonReader {
  const JsonReader._();

  static String asString(Object? value, {String fallback = ''}) =>
      value?.toString() ?? fallback;

  static String? asStringOrNull(Object? value) => value?.toString();

  static int asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? asIntOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double asDouble(Object? value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double? asDoubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool asBool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    final String raw = value?.toString().toLowerCase() ?? '';
    if (raw.isEmpty) return fallback;
    return raw == 'true' || raw == '1' || raw == 'yes' || raw == 't';
  }

  static DateTime? asDateOrNull(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static DateTime asDate(Object? value, {DateTime? fallback}) =>
      asDateOrNull(value) ?? fallback ?? DateTime.fromMillisecondsSinceEpoch(0);

  static List<String> asStringList(Object? value) {
    if (value is List) {
      return value.map((Object? e) => e.toString()).toList(growable: false);
    }
    if (value is String && value.isNotEmpty) {
      return value.split(',').map((String e) => e.trim()).toList();
    }
    return const <String>[];
  }

  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static Map<String, dynamic>? asMapOrNull(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  /// Maps a JSON array into a typed list using [fromJson].
  static List<T> asModelList<T>(
    Object? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value is! List) return <T>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> e) => fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Resolves an enum from its `name`, falling back when absent/unknown.
  static T asEnum<T extends Enum>(
    Object? value,
    List<T> values,
    T fallback,
  ) {
    final String raw = value?.toString() ?? '';
    for (final T candidate in values) {
      if (candidate.name == raw) return candidate;
    }
    return fallback;
  }
}

/// Strips `null` values so `toJson()` output can be sent straight to Supabase
/// without overwriting columns with nulls on partial updates.
extension JsonMapCompact on Map<String, dynamic> {
  Map<String, dynamic> compact() {
    final Map<String, dynamic> out = <String, dynamic>{};
    forEach((String key, dynamic value) {
      if (value != null) out[key] = value;
    });
    return out;
  }
}
