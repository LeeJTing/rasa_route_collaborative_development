import 'dart:developer' as developer;
import 'dart:typed_data';

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
      // Google OAuth returns through the `com.rasaroute.app://login-callback`
      // deep link; PKCE is the flow that pairs with a custom-scheme redirect
      // on mobile (and the default here - this makes it explicit). Remember
      // to whitelist that redirect URL in the Supabase project's auth
      // settings, or the OAuth redirect is rejected before the app is
      // reopened.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
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

  /// Uploads raw bytes to a storage bucket and returns the object path the
  /// bucket assigned - stored as the row's `image_id` (and turned into the
  /// public `image_url` via [storagePublicUrl]). Throws on failure - the
  /// caller surfaces the error to the tourist. Uses `uploadBinary`, which
  /// works on every platform (dart:io `File` is unavailable on web).
  Future<String> uploadBytes({
    required String bucket,
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    return _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
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
    Map<String, List<Object?>>? inFilter,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    dynamic query = _client.from(table).select(columns);
    for (final MapEntry<String, Object?> filter in eq.entries) {
      query = query.eq(filter.key, filter.value as Object);
    }
    final Map<String, List<Object?>> inValues =
        inFilter ?? const <String, List<Object?>>{};
    for (final MapEntry<String, List<Object?>> filter in inValues.entries) {
      if (filter.value.isEmpty) continue;
      query = query.inFilter(filter.key, filter.value);
    }
    if (orderBy != null) {
      query = query.order(orderBy, ascending: ascending);
    }
    if (limit != null) {
      query = query.limit(limit);
    }
    if (rangeStart != null && rangeEnd != null) {
      query = query.range(rangeStart, rangeEnd);
    }
    final List<dynamic> rows = await query as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------------
  // Paging
  // ---------------------------------------------------------------------------
  //
  // PostgREST will not stream a whole table. A select with no `Range` header is
  // answered with at most `max-rows` rows - 1000 on a Supabase project - and
  // **says nothing about it**: no error, no flag, just a short array. A table
  // that outgrows that ceiling therefore looks to the app as though most of its
  // rows had been deleted. Every read of a table that can pass 1000 rows has to
  // page, which is what [selectEvery] does.

  /// Rows per request. Must not exceed the project's `max-rows` setting, or
  /// every request silently loses the tail of its page.
  static const int selectPageSize = 1000;

  /// Hard stop on the paging loop. 400 pages is 400k rows - far past anything
  /// this app reads - so reaching it means something is wrong, and returning
  /// what we have beats looping forever.
  static const int selectMaxPages = 400;

  /// Pages requested at once. Paging one page after another turns a 78k-row
  /// table into 79 sequential round trips, which on mobile latency alone is
  /// slower than the query will ever be; asking for a wave of pages together
  /// collapses that to a handful of waits. Kept small so a phone is not opening
  /// a burst of sockets.
  static const int selectPagesInFlight = 8;

  /// `select` returning **every** matching row, page by page.
  ///
  /// [orderBy] is required and must be unique (the primary key): `range` paging
  /// is only stable if the server sorts the same way for every page. Ordering
  /// by a non-unique column lets rows move between pages, which duplicates some
  /// and skips others.
  Future<List<Map<String, dynamic>>> selectEvery(
    String table, {
    required String orderBy,
    String columns = '*',
    Map<String, Object?> eq = const <String, Object?>{},
    Map<String, List<Object?>>? inFilter,
    bool ascending = true,
    int pageSize = selectPageSize,
  }) async {
    final List<Map<String, dynamic>> all = <Map<String, dynamic>>[];
    int page = 0;
    while (page < selectMaxPages) {
      final List<Future<List<Map<String, dynamic>>>> wave =
          <Future<List<Map<String, dynamic>>>>[];
      final int remaining = selectMaxPages - page;
      final int pagesThisWave = selectPagesInFlight < remaining
          ? selectPagesInFlight
          : remaining;
      for (int i = 0; i < pagesThisWave; i++) {
        final int start = (page + i) * pageSize;
        wave.add(
          selectAll(
            table,
            columns: columns,
            eq: eq,
            inFilter: inFilter,
            orderBy: orderBy,
            ascending: ascending,
            rangeStart: start,
            rangeEnd: start + pageSize - 1,
          ),
        );
      }

      final List<List<Map<String, dynamic>>> pages = await Future.wait(wave);
      bool reachedEnd = false;
      for (final List<Map<String, dynamic>> rows in pages) {
        all.addAll(rows);
        // Only the last page can be short, and everything after it is empty -
        // so a short page anywhere in the wave means the table is exhausted.
        if (rows.length < pageSize) reachedEnd = true;
      }
      if (reachedEnd) break;
      page += wave.length;
    }
    return all;
  }

  /// How many rows a table holds, without downloading any of them - a `HEAD`
  /// request answered by the `Content-Range` header.
  Future<int> countRows(String table) async =>
      await _client.from(table).count(CountOption.exact);

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

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Returns the current authentication session as a plain map.
  ///
  /// Supabase SDK objects remain inside the external layer.
  Future<Map<String, dynamic>?> getCurrentAuthSession() async {
    if (!_isReady) return null;

    final Session? session = Supabase.instance.client.auth.currentSession;
    final User? user = Supabase.instance.client.auth.currentUser;

    if (session == null || user == null) return null;

    return _authSessionToMap(session: session, user: user);
  }

  /// Sends an email OTP for passwordless sign-in.
  ///
  /// Depending on the Supabase project's auth configuration, a new user may
  /// be created automatically when the email does not already exist.
  Future<void> sendEmailOtp({required String email}) async {
    try {
      await _client.auth.signInWithOtp(email: email);
    } on AuthException catch (error) {
      // Keep the SDK's raw exception (message + statusCode + code) inside the
      // external layer - an invalid/unknown address is a normal user error,
      // not something to dump on the sign-in screen.
      developer.log(
        'Email OTP send rejected.',
        name: 'SupabaseService',
        error: error,
      );
      // A 429 / "rate limit" rejection means a code was emailed very recently
      // (Supabase enforces its own send-frequency cap on top of the app's
      // 3-per-10 gate). Telling the tourist their email is wrong would be
      // misleading, so translate that case separately.
      final String message = error.message.toLowerCase();
      final String status = (error.statusCode ?? '').toLowerCase();
      final String code = (error.code ?? '').toLowerCase();
      final bool rateLimited =
          status == '429' ||
          code.contains('rate_limit') ||
          message.contains('rate limit') ||
          message.contains('too many');
      throw Exception(
        rateLimited
            ? 'Too many attempts, please try again later.'
            : 'Unable to send the code. Check that your email address is '
                  'correct and try again.',
      );
    }
  }

  /// Verifies an email OTP and returns the resulting session as a plain map.
  ///
  /// Supabase SDK objects do not leave this external layer.
  ///
  /// A wrong or expired code arrives as an [AuthException] from the SDK; its
  /// raw form ("message + statusCode + code") must never be shown to the
  /// tourist, so it is translated here into a plain, user-facing [Exception]
  /// before it can leave this layer.
  Future<Map<String, dynamic>?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final AuthResponse response;
    try {
      response = await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
    } on AuthException catch (error) {
      developer.log(
        'Email OTP verify rejected.',
        name: 'SupabaseService',
        error: error,
      );
      // Supabase reports both a wrong code and an expired code as
      // `otp_expired` ("Token has expired or is invalid").
      if (error.code == 'otp_expired') {
        throw Exception(
          'That verification code is invalid or has expired. '
          'Please try again or request a new code.',
        );
      }
      throw Exception('Unable to verify the code. Please try again.');
    }

    final Session? session = response.session;
    final User? user = response.user;

    if (session == null || user == null) return null;

    return _authSessionToMap(session: session, user: user);
  }

  /// Starts Google OAuth sign-in.
  ///
  /// Returns true when Supabase successfully launches the OAuth flow.
  Future<bool> signInWithGoogle({required String redirectTo}) async {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
  }

  /// Signs out the current Supabase user.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Map<String, dynamic> _authSessionToMap({
    required Session session,
    required User user,
  }) {
    return <String, dynamic>{
      'access_token': session.accessToken,
      'refresh_token': session.refreshToken,
      'user_id': user.id,
      'email': user.email,
      'expires_at': session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              session.expiresAt! * 1000,
              isUtc: true,
            ).toIso8601String(),
    };
  }
  //End of Authentication -------------------------------------------------------
}
