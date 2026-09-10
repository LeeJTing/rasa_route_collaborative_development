import 'dart:async';

import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `OtpView`.
///
/// Six-digit code entry.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class OtpViewModel extends BaseViewModel {
  OtpViewModel({@visibleForTesting TouristInformationLogicFacade? touristLogic})
    : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  static const int otpLength = 6;

  /// Seconds a tourist must wait before requesting another code - mirrors the
  /// server's 60s email-frequency limit, shown as "Resend OTP in 60s".
  static const int resendCooldownSeconds = 60;

  /// How long a sent code is treated as "still pending & reusable" before the
  /// screen falls back to requesting a fresh one. Mirrors Supabase's default
  /// email-OTP expiry (1 hour); adjust here if the project configures a
  /// different expiry.
  static const Duration otpPendingValidity = Duration(hours: 1);

  /// Email supplied by the View from the route argument. The login screen no
  /// longer sends an OTP - it only navigates here, so the email travels with
  /// the route and this screen owns sending.
  String emailArgument = '';

  String _email = '';
  String _token = '';
  bool _verified = false;
  bool _needsProfileSetup = false;
  bool _reusingExistingCode = false;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  String get email => _email;
  String get token => _token;
  bool get verified => _verified;

  /// C3 first-run gate: true when the verified tourist has configured no
  /// profile yet, so the View routes them to set-up before the dashboard.
  bool get needsProfileSetup => _needsProfileSetup;

  bool get canVerify =>
      _email.isNotEmpty && _token.length == otpLength && !isBusy;

  /// Seconds left before the code can be resent; 0 means it can be resent now.
  int get resendCooldown => _resendCooldown;

  bool get canResend => _resendCooldown <= 0 && !isBusy;

  /// True while a code request is actually in flight (the entry send or a
  /// resend). The View shows a small "sending your code" note instead of
  /// pretending a code has already arrived.
  bool get isSendingCode =>
      isBusy && !hasError && _resendCooldown == 0 && _token.length < otpLength;

  /// True when a code for this address was already sent recently and is still
  /// usable, so no fresh email is on its way - the View shows a hint like
  /// "check your inbox, the earlier code still works" instead of pretending a
  /// new code is being sent.
  bool get reusingExistingCode => _reusingExistingCode;

  @override
  Future<void> onInit() async {
    _email = (emailArgument.isNotEmpty
            ? emailArgument
            : touristLogic.pendingAuthEmail)
        .trim();
    if (_email.isEmpty) {
      setError(StateError('Enter your email address before verifying a code.'));
      return;
    }
    safeNotifyListeners();
    await _ensureCodeReady();
  }

  /// Option B: this screen decides whether a fresh code actually needs to be
  /// sent. If a code is already pending for this address and is still within
  /// its validity window, reuse it (do not hit the server's 60s limit again);
  /// otherwise request a new code now, surfacing the 3-per-10 gate error here.
  Future<void> _ensureCodeReady() async {
    if (_hasReusablePendingCode(_email)) {
      _reusingExistingCode = true;
      _resumeCountdownFromPendingCode();
      return;
    }
    _reusingExistingCode = false;
    await _requestCode();
  }

  /// The pending code's send time, but only when it belongs to [email] and is
  /// still within its validity window.
  bool _hasReusablePendingCode(String email) {
    final DateTime? sentAt = _pendingOtpSentAtFor(email);
    return sentAt != null &&
        DateTime.now().difference(sentAt) < otpPendingValidity;
  }

  /// The pending code's send time, but only when it belongs to [email].
  DateTime? _pendingOtpSentAtFor(String email) {
    if (touristLogic.pendingAuthEmail != email) return null;
    return touristLogic.pendingOtpSentAt;
  }

  /// Resumes the resend countdown so it reflects when the existing code was
  /// actually sent (the server refuses a new one until that mark anyway).
  void _resumeCountdownFromPendingCode() {
    final DateTime? sentAt = _pendingOtpSentAtFor(_email);
    if (sentAt == null) {
      _startResendCooldown();
      return;
    }
    final int ageSeconds = DateTime.now().difference(sentAt).inSeconds;
    final int remaining = (resendCooldownSeconds - ageSeconds).clamp(
      0,
      resendCooldownSeconds,
    );
    _startResendCooldown(remaining);
  }

  /// Sends a fresh code. A rejection (the app's 3-per-10 gate or the server's
  /// own frequency cap) keeps its friendly message visible and runs a cooldown
  /// so the Resend control is never a clickable-but-silent no-op. If an earlier
  /// code for this address is still usable, it is still surfaced as a hint, but
  /// the rejection itself is never swallowed.
  Future<void> _requestCode() async {
    await runGuarded(() => touristLogic.sendEmailOtp(_email));
    if (hasError) {
      // Do NOT clear the error: the tourist pressed Resend and must see why it
      // did not go through (e.g. "Too many attempts, please try again later.").
      // Keep telling them the earlier code (if any) is still usable, and run a
      // cooldown so the button cannot be hammered silently.
      _reusingExistingCode = _hasReusablePendingCode(_email);
      _startResendCooldown();
      return;
    }
    _reusingExistingCode = false;
    _startResendCooldown();
  }

  void setToken(String value) {
    _token = value.replaceAll(RegExp(r'\s'), '');
    safeNotifyListeners();
  }

  Future<void> verifyEmailOtp() async {
    _verified = false;
    await runGuarded(() async {
      final session = await touristLogic.verifyEmailOtp(
        email: _email,
        token: _token,
      );
      if (session == null) {
        throw StateError('That verification code is invalid or has expired.');
      }
      _verified = true;
      _needsProfileSetup = await touristLogic.needsProfileSetup();
    });
  }

  /// Requests another code. No-op while the resend countdown is still
  /// running; a successful resend restarts the countdown. A rejection (e.g.
  /// the app's 3-per-10 gate) keeps its message visible and runs a cooldown,
  /// so the button is never a clickable-but-silent no-op.
  Future<void> resendEmailOtp() async {
    if (!canResend) return;
    await _requestCode();
  }

  void _startResendCooldown([int seconds = resendCooldownSeconds]) {
    _resendTimer?.cancel();
    _resendCooldown = seconds < 0 ? 0 : seconds;
    safeNotifyListeners();
    if (_resendCooldown <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _resendCooldown--;
      if (_resendCooldown <= 0) {
        _resendCooldown = 0;
        _resendTimer?.cancel();
        _resendTimer = null;
      }
      safeNotifyListeners();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _resendTimer = null;
    super.dispose();
  }
}
