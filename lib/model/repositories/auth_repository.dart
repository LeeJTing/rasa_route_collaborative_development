import 'dart:math' as math;

import '../../domain_model/auth_session.dart';
import '../../domain_model/tourist.dart';
import '../../model/data_models/auth_session_data_model.dart';
import '../../model/data_models/tourist_data_model.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';

/// Sign-in, sign-up, OTP and session persistence.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class AuthRepository {
  AuthRepository();

  final APIManager api = APIManager();
  final LocalStorageManager storage = LocalStorageManager();

  /// The email address for the in-progress passwordless sign-in.
  ///
  /// This is intentionally transient: the OTP view only needs it while the
  /// app remains open, and a session must never be created until verification
  /// succeeds.
  static String _pendingEmail = '';

  // ==========================================================================
  // Account provisioning.
  //
  // The UX has no separate "register" screen: a tourist picks an auth method
  // (email OTP or Google), and the first successful authentication
  // auto-creates the `tourist` row. Login and register are the same flow.
  //
  // `Tourist.touristId` (`tourist.tourist_id`) is what the rest of the app
  // uses as a foreign key; `Tourist.authUserId` (`tourist.id`) is the
  // Supabase auth user id. They are different columns - see
  // `TouristDataModel`.
  // ==========================================================================

  /// The signed-in tourist's id, or null if nobody is signed in.
  ///
  /// Resolves through the authenticated session to the real `tourist_id`,
  /// auto-creating the `tourist` row on first sign-in. Null when there is no
  /// session - callers (e.g. the profile and landmark modules) already treat
  /// null as "not signed in / nothing to show".
  Future<String?> currentTouristId() async {
    final AuthSession? session = await getCurrentSession();
    if (session == null) return null;
    final Tourist? tourist = await getOrCreateTourist(session);
    return tourist?.touristId;
  }

  /// Returns the `tourist` row for [session]'s auth user, creating it on
  /// first sign-in ("auto register"). `null` when the row cannot be resolved
  /// or created (e.g. RLS denies the insert - see Known Gaps).
  Future<Tourist?> getOrCreateTourist(AuthSession session) async {
    final Map<String, dynamic>? existing = await api.selectOne(
      APIManager.tableTourist,
      columns: 'tourist_id, id',
      eq: <String, Object?>{'id': session.userId},
    );
    if (existing != null) {
      return _toTouristDomain(
        TouristDataModel.fromJson(existing),
        session.email,
      );
    }

    // No row yet - the account was authenticated for the first time, so
    // provision it. `tourist_id` is supplied here (a v4 UUID) rather than
    // relying on a DB default, so the insert works whether or not the column
    // is identity.
    final Map<String, dynamic>? inserted = await api.insertRowReturning(
      APIManager.tableTourist,
      <String, dynamic>{'tourist_id': _newUuid(), 'id': session.userId},
    );
    if (inserted == null) return null;
    return _toTouristDomain(TouristDataModel.fromJson(inserted), session.email);
  }

  /// Sends a passwordless OTP to [email].
  Future<void> sendEmailOtp(String email) async {
    final String normalizedEmail = email.trim();
    await api.sendEmailOtp(email: normalizedEmail);
    _pendingEmail = normalizedEmail;
  }

  /// The email address currently awaiting OTP verification.
  String get pendingEmail => _pendingEmail;

  /// Verifies an email OTP and returns the authenticated domain session.
  ///
  /// Returns null when Supabase does not provide a valid session. The session
  /// is cached locally so the rest of the app can resolve the tourist
  /// (`currentTouristId`) without re-hitting Supabase.
  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final Map<String, dynamic>? row = await api.verifyEmailOtp(
      email: email.trim(),
      token: token.trim(),
    );

    if (row == null) return null;

    final AuthSessionDataModel data = AuthSessionDataModel.fromJson(row);
    final AuthSession session = _toDomain(data);
    await _saveSession(session);

    return session;
  }

  /// Starts the Google OAuth flow.
  Future<bool> signInWithGoogle({required String redirectTo}) {
    return api.signInWithGoogle(redirectTo: redirectTo);
  }

  /// Returns the currently authenticated session, if one exists.
  ///
  /// Checks the local cache first (a session that was saved here is newer
  /// than what this process can re-derive), then falls back to Supabase -
  /// e.g. right after a Google OAuth deep link completes the exchange while
  /// this class had never seen the session. Anything found is cached.
  Future<AuthSession?> getCurrentSession() async {
    final AuthSession? stored = await getStoredSession();
    if (stored != null) return stored;

    final Map<String, dynamic>? row = await api.getCurrentAuthSession();
    if (row == null) return null;

    final AuthSessionDataModel data = AuthSessionDataModel.fromJson(row);
    final AuthSession session = _toDomain(data);
    await _saveSession(session);

    return session;
  }

  /// The locally cached session, or null when none has been saved yet.
  Future<AuthSession?> getStoredSession() async {
    final Map<String, dynamic>? json = storage.readJson(
      LocalStorageManager.keyAuthSession,
    );
    if (json == null) return null;
    try {
      return _toDomain(AuthSessionDataModel.fromJson(json));
    } catch (_) {
      // Corrupt cache - drop it rather than surface it forever.
      await clearStoredSession();
      return null;
    }
  }

  /// Persists [session] so it survives a ViewModel rebuild (and, once
  /// `LocalStorageManager` is backed by real storage, an app restart).
  Future<void> _saveSession(AuthSession session) => storage.writeJson(
    LocalStorageManager.keyAuthSession,
    AuthSessionDataModel(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      userId: session.userId,
      email: session.email,
      expiresAt: session.expiresAt,
    ).toJson(),
  );

  /// Removes the locally cached session.
  Future<void> clearStoredSession() =>
      storage.remove(LocalStorageManager.keyAuthSession);

  /// Signs out the current user and drops the local session cache.
  Future<void> signOut() async {
    await api.signOut();
    await clearStoredSession();
  }

  /// Returns the authenticated Supabase user id, or an empty string.
  String get currentUserId => api.currentUserId;

  /// Converts the data-layer representation into the domain model.
  AuthSession _toDomain(AuthSessionDataModel data) {
    return AuthSession(
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      userId: data.userId,
      email: data.email,
      expiresAt: data.expiresAt,
    );
  }

  /// `tourist` row -> domain. Only identity fields are known here - profile
  /// fields (food preference, dietary restrictions) are filled in later by
  /// `TouristProfileRepository`, which is a separate, richer query. Keeping
  /// them unset here is exactly why `Tourist` defaults them (empty list /
  /// null) - auth answers "who is the tourist?", not "what do they like?".
  Tourist _toTouristDomain(TouristDataModel data, String email) {
    return Tourist(
      touristId: data.touristId,
      authUserId: data.authUserId,
      email: data.email ?? email,
      displayName: data.displayName ?? '',
    );
  }

  /// A v4 (random) UUID, used for the `tourist_id` of an auto-created
  /// `tourist` row. Standard format, no dependency needed.
  static String _newUuid() {
    final math.Random random = math.Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final String hex = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
