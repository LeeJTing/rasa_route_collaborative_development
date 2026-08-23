import 'package:rasa_route_collaborative_development/app/config/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper around the Supabase SDK.
///
/// External services are the only place a third-party SDK is imported. Nothing
/// above `APIManager` may touch this class - a repository asks `APIManager`
/// for rows, never `Supabase.instance` directly.
///
/// A singleton: `SupabaseService()` always returns the same instance, so the
/// connection is shared without anyone having to pass it around.
class SupabaseService {
  factory SupabaseService() => _instance;

  SupabaseService._();

  static final SupabaseService _instance = SupabaseService._();

  static bool _isReady = false;

  static Future<void> initialise() async {
    if (Env.supabaseUrl.isEmpty || Env.supabasePublishableKey.isEmpty) {
      return;
    }
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
    _isReady = true;
  }

  SupabaseClient get _client {
    if (!_isReady) {
      throw StateError('Supabase is not configured for this build.');
    }
    return Supabase.instance.client;
  }

  /// The signed-in user's id, or `''` when nobody is signed in.
  String get currentUserId =>
      _isReady ? Supabase.instance.client.auth.currentUser?.id ?? '' : '';

  String storagePublicUrl(String bucket, String path) {
    final String base = Env.supabaseUrl;
    final String normalizedBase = base.endsWith('/') ? base : '$base/';
    final String encodedPath = path
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return '${normalizedBase}storage/v1/object/public/$bucket/$encodedPath';
  }

  // ---------------------------------------------------------------------------
  // Generic row access. Every repository goes through these - table names and
  // select strings live in the repository, error translation lives here.
  // ---------------------------------------------------------------------------

  /// `select` returning every matching row.
  Future<List<Map<String, dynamic>>> selectAll(
    String table, {
    String columns = '*',
    Map<String, Object?> eq = const <String, Object?>{},
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    dynamic query = _client.from(table).select(columns);
    for (final MapEntry<String, Object?> filter in eq.entries) {
      query = query.eq(filter.key, filter.value as Object);
    }
    if (orderBy != null) {
      query = query.order(orderBy, ascending: ascending);
    }
    if (limit != null) {
      query = query.limit(limit);
    }
    final List<dynamic> rows = await query as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  /// `select` returning at most one row, or `null` when there isn't one.
  Future<Map<String, dynamic>?> selectOne(
    String table, {
    String columns = '*',
    required Map<String, Object?> eq,
  }) async {
    dynamic query = _client.from(table).select(columns);
    for (final MapEntry<String, Object?> filter in eq.entries) {
      query = query.eq(filter.key, filter.value as Object);
    }
    final Map<String, dynamic>? row =
        await query.maybeSingle() as Map<String, dynamic>?;
    return row;
  }

  Future<void> insertRow(String table, Map<String, dynamic> values) async {
    await _client.from(table).insert(values);
  }

  /// `insert` returning the inserted row back - used when the DB assigns a
  /// generated id (identity column, e.g. `landmark_item.landmark_item_id`)
  /// that the caller needs.
  Future<Map<String, dynamic>?> insertRowReturning(
    String table,
    Map<String, dynamic> values,
  ) async {
    final List<dynamic> rows =
        await _client.from(table).insert(values).select() as List<dynamic>;
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  Future<void> deleteRows(
    String table, {
    required Map<String, Object?> eq,
  }) async {
    dynamic query = _client.from(table).delete();
    for (final MapEntry<String, Object?> filter in eq.entries) {
      query = query.eq(filter.key, filter.value as Object);
    }
    await query;
  }

  /// `update` the rows matching [eq], setting [values].
  Future<void> updateRow(
    String table,
    Map<String, Object?> values, {
    required Map<String, Object?> eq,
  }) async {
    dynamic query = _client.from(table).update(values);
    for (final MapEntry<String, Object?> filter in eq.entries) {
      query = query.eq(filter.key, filter.value as Object);
    }
    await query;
  }
}
