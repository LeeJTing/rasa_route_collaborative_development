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
  /// A session must never be created until verification succeeds, so this is
  /// only a hint for the OTP screen - but it is persisted now (see the
  /// pending-OTP marker below), so a code sent just before the app is killed
  /// is still recognised as pending on the next launch.
  static String _pendingEmail = '';

  // ==========================================================================
  // Pending OTP tracking (Auth - ChinShunYon) - powers the Option B flow.
  //
  // The OTP screen owns "send a new code or not". When the tourist lands on
  // it (login now only navigates), it asks whether a code was already sent to
  // this email and is still reusable (not consumed). That decision needs the
  // time the freshest code was sent plus a "consumed" flag, which is why this
  // marker lives apart from the rate-limit history in `otp_send_history`
  // (that list must survive verification so the 3-per-10 gate keeps counting).
  //
  // The marker is PERSISTED, with the statics below as a process cache. It
  // used to be memory-only, while the device-wide cooldown it overlaps with
  // (`otp_device_send_at`) did survive a kill - so a relaunch inside that
  // window could no longer tell "a code was already sent": it fired a send,
  // got refused by the device gate, and restarted a fresh 60s countdown that
  // disagreed with the gate's own clock on every re-entry.
  // ==========================================================================
  static const String _pendingEmailKey = 'otp_pending_email';
  static const String _pendingOtpSentAtKey = 'otp_pending_sent_at';

  static DateTime? _pendingOtpSentAt;

  /// When the freshest code for the pending email was sent, or null when no
  /// code is currently pending. Cleared once that code is verified.
  ///
  /// Reads through to the persisted copy (and caches it) so the marker also
  /// survives an app restart.
  DateTime? get pendingOtpSentAt {
    if (_pendingOtpSentAt != null) return _pendingOtpSentAt;
    final String? raw = storage.readString(_pendingOtpSentAtKey);
    _pendingOtpSentAt = raw == null ? null : DateTime.tryParse(raw);
    return _pendingOtpSentAt;
  }

  /// Marks the pending email's freshest code as sent at [sentAt]. Called by
  /// [sendEmailOtp] after the server accepts the send.
  Future<void> recordPendingOtpSentAt(DateTime sentAt) async {
    _pendingOtpSentAt = sentAt;
    await storage.writeString(_pendingOtpSentAtKey, sentAt.toIso8601String());
  }

  /// Forgets the pending email and its code - called once a code is verified
  /// so a later sign-in with the same email must request a fresh code.
  Future<void> clearPendingOtp() async {
    _pendingEmail = '';
    _pendingOtpSentAt = null;
    await storage.remove(_pendingEmailKey);
    await storage.remove(_pendingOtpSentAtKey);
  }
  // ==========================================================================
  // End of pending OTP tracking (Auth - ChinShunYon)
  // ==========================================================================

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

  /// True when the sign-in that just completed CREATED the `tourist` row -
  /// that account's first ever authentication. Set by [getOrCreateTourist] and
  /// cleared on sign-out; read by the first-run set-up gate, which must not ask
  /// an account that already exists (see `UserProfileLogic.needsProfileSetup`).
  ///
  /// STATIC like the pending-OTP marker: every logic facade builds its own
  /// `AuthRepository`, so the sign-in path (which sets it) and the profile path
  /// (which reads it) must share one value.
  static bool _accountJustCreated = false;

  bool get accountJustCreated => _accountJustCreated;

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
    // The row was CREATED, so this authentication is the account's first ever -
    // the one moment the first-run set-up screen belongs to.
    _accountJustCreated = true;
    return _toTouristDomain(TouristDataModel.fromJson(inserted), session.email);
  }

  /// Sends a passwordless OTP to [email].
  Future<void> sendEmailOtp(String email) async {
    final String normalizedEmail = email.trim();
    await api.sendEmailOtp(email: normalizedEmail);
    _pendingEmail = normalizedEmail;
    await storage.writeString(_pendingEmailKey, normalizedEmail);
    await recordPendingOtpSentAt(DateTime.now());
  }

  /// The email address currently awaiting OTP verification.
  String get pendingEmail {
    if (_pendingEmail.isNotEmpty) return _pendingEmail;
    _pendingEmail = storage.readString(_pendingEmailKey) ?? '';
    return _pendingEmail;
  }

  // ==========================================================================
  // OTP send history (Auth - ChinShunYon) - powers the 3-per-10-min gate.
  //
  // Only successful sends are recorded (recorded after `sendEmailOtp`
  // returns), so an address that keeps getting rejected never burns its quota.
  // ==========================================================================

  static const String _otpSendHistoryKey = 'otp_send_history';

  /// Every recorded OTP send timestamp for [email], oldest first.
  Future<List<DateTime>> otpSendTimes(String email) async {
    final Map<String, dynamic>? history = storage.readJson(_otpSendHistoryKey);
    if (history == null) return const <DateTime>[];
    final Object? raw = history[email.trim().toLowerCase()];
    if (raw is! List) return const <DateTime>[];
    return raw
        .whereType<String>()
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .toList(growable: false);
  }

  /// Appends a successful send for [email]. Old entries (past 1 day) are
  /// pruned so the stored list never grows without bound.
  Future<void> recordOtpSend(String email) async {
    final String key = email.trim().toLowerCase();
    final Map<String, dynamic> history =
        storage.readJson(_otpSendHistoryKey) ?? <String, dynamic>{};
    // `otpSendTimes` returns an unmodifiable list - copy it so a send can be
    // appended (adding in place used to throw and made every send look like a
    // failure, which broke the 3-per-10 gate and the resend countdown).
    final List<DateTime> times = List<DateTime>.of(await otpSendTimes(email));
    times.add(DateTime.now());
    final DateTime cutoff = DateTime.now().subtract(const Duration(days: 1));
    final List<String> iso = times
        .where((DateTime t) => t.isAfter(cutoff))
        .map((DateTime t) => t.toIso8601String())
        .toList(growable: false);
    history[key] = iso;
    await storage.writeJson(_otpSendHistoryKey, history);
    // Every send also stamps the DEVICE, not just this address.
    await storage.writeString(
      _otpDeviceSendKey,
      DateTime.now().toIso8601String(),
    );
  }
  // ==========================================================================
  // End of OTP send history (Auth - ChinShunYon)
  // ==========================================================================

  // ==========================================================================
  // OTP device cooldown marker (Auth - ChinShunYon) - the resend wait is per
  // DEVICE, so switching accounts cannot buy a fresh allowance. Written by
  // `recordOtpSend` above, read by the send gate in `AuthenticateLogic`.
  // ==========================================================================

  static const String _otpDeviceSendKey = 'otp_device_send_at';

  /// When this device last sent ANY OTP, for any address, or null when it has
  /// not sent one yet.
  DateTime? get otpLastDeviceSendAt {
    final String? raw = storage.readString(_otpDeviceSendKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
  // ==========================================================================
  // End of OTP device cooldown marker (Auth - ChinShunYon)
  // ==========================================================================

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

    // The pending code has been consumed - a later sign-in for the same
    // address must request a brand-new code rather than reusing this one.
    await clearPendingOtp();

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
    // The "account was just created" mark belongs to the session that left.
    _accountJustCreated = false;
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
