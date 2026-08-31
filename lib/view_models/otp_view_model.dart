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

  /// Seconds a tourist must wait before requesting another code - the OTP
  /// screen's "Resend OTP in 60s" countdown (mock-up).
  static const int resendCooldownSeconds = 60;

  String _email = '';
  String _token = '';
  bool _verified = false;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  String get email => _email;
  String get token => _token;
  bool get verified => _verified;
  bool get canVerify =>
      _email.isNotEmpty && _token.length == otpLength && !isBusy;

  /// Seconds left before the code can be resent; 0 means it can be resent now.
  int get resendCooldown => _resendCooldown;

  bool get canResend => _resendCooldown <= 0 && !isBusy;

  @override
  Future<void> onInit() async {
    _email = touristLogic.pendingAuthEmail;
    if (_email.isEmpty) {
      setError(StateError('Enter your email address before verifying a code.'));
      return;
    }
    safeNotifyListeners();
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
    });
  }

  /// Requests another code. No-op while the resend countdown is still
  /// running; a successful resend restarts the countdown.
  Future<void> resendEmailOtp() async {
    if (!canResend) return;
    await runGuarded(() async {
      await touristLogic.sendEmailOtp(_email);
    });
    if (!hasError) _startResendCooldown();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _resendCooldown = resendCooldownSeconds;
    safeNotifyListeners();
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
