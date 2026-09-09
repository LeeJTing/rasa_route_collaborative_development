import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/otp_view_model.dart';

void main() {
  group('OtpViewModel', () {
    test('onInit loads the pending email from the facade', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          pendingEmail: 'a@b.com',
        ),
      );
      addTearDown(viewModel.dispose);

      await viewModel.onInit();

      expect(viewModel.email, 'a@b.com');
      expect(viewModel.hasError, isFalse);
    });

    test('onInit reports an error when no email is pending', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );
      addTearDown(viewModel.dispose);

      await viewModel.onInit();

      expect(viewModel.hasError, isTrue);
    });

    test('canVerify requires exactly 6 digits', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          pendingEmail: 'a@b.com',
        ),
      );
      addTearDown(viewModel.dispose);
      await viewModel.onInit();

      viewModel.setToken('12345');

      expect(viewModel.canVerify, isFalse);

      viewModel.setToken('123456');

      expect(viewModel.canVerify, isTrue);
    });

    test('setToken strips whitespace', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          pendingEmail: 'a@b.com',
        ),
      );
      addTearDown(viewModel.dispose);
      await viewModel.onInit();

      viewModel.setToken(' 1 2 3 4 5 6 ');

      expect(viewModel.token, '123456');
    });

    test('verifyEmailOtp sets verified on success', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          pendingEmail: 'a@b.com',
          verifyResult: _session,
        ),
      );
      addTearDown(viewModel.dispose);
      await viewModel.onInit();
      viewModel.setToken('123456');

      await viewModel.verifyEmailOtp();

      expect(viewModel.verified, isTrue);
      expect(viewModel.state, ViewState.ready);
      expect(viewModel.hasError, isFalse);
    });

    test('verifyEmailOtp surfaces an error when the code is invalid', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          pendingEmail: 'a@b.com',
          verifyResult: null,
        ),
      );
      addTearDown(viewModel.dispose);
      await viewModel.onInit();
      viewModel.setToken('123456');

      await viewModel.verifyEmailOtp();

      expect(viewModel.verified, isFalse);
      expect(viewModel.hasError, isTrue);
      // The message is a plain sentence - never a "Bad state: ..." prefix.
      expect(
        viewModel.errorMessage,
        'That verification code is invalid or has expired.',
      );
    });

    test(
      'verifyEmailOtp shows the friendly message when Supabase rejects the code',
      () async {
        // SupabaseService translates the raw SDK AuthApiException into this
        // plain Exception - the UI must show exactly that sentence, with no
        // 'Exception:'/'AuthApiException(...)' internals leaking through.
        final OtpViewModel viewModel = OtpViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            pendingEmail: 'a@b.com',
            verifyError: Exception(
              'That verification code is invalid or has expired. '
              'Please try again or request a new code.',
            ),
          ),
        );
        addTearDown(viewModel.dispose);
        await viewModel.onInit();
        viewModel.setToken('123456');

        await viewModel.verifyEmailOtp();

        expect(viewModel.verified, isFalse);
        expect(viewModel.hasError, isTrue);
        expect(
          viewModel.errorMessage,
          'That verification code is invalid or has expired. '
          'Please try again or request a new code.',
        );
      },
    );

    group('resend countdown', () {
      test('starts at 45 seconds and counts down to zero', () {
        fakeAsync((FakeAsync async) {
          final OtpViewModel viewModel = OtpViewModel(
            touristLogic: _FakeTouristInformationLogicFacade(
              pendingEmail: 'a@b.com',
            ),
          );
          viewModel.onInit();
          async.flushMicrotasks();

          expect(viewModel.resendCooldown, OtpViewModel.resendCooldownSeconds);
          expect(viewModel.canResend, isFalse);

          async.elapse(
            const Duration(seconds: OtpViewModel.resendCooldownSeconds),
          );

          expect(viewModel.resendCooldown, 0);
          expect(viewModel.canResend, isTrue);
          viewModel.dispose();
        });
      });

      test('does not send a new code while still cooling down', () {
        fakeAsync((FakeAsync async) {
          final _FakeTouristInformationLogicFacade facade =
              _FakeTouristInformationLogicFacade(pendingEmail: 'a@b.com');
          final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
          viewModel.onInit();
          async.flushMicrotasks();

          viewModel.resendEmailOtp();
          async.flushMicrotasks();

          expect(facade.resendCount, 0);
          expect(viewModel.resendCooldown, OtpViewModel.resendCooldownSeconds);
          viewModel.dispose();
        });
      });

      test('restarts the countdown after a successful resend', () {
        fakeAsync((FakeAsync async) {
          final _FakeTouristInformationLogicFacade facade =
              _FakeTouristInformationLogicFacade(pendingEmail: 'a@b.com');
          final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
          viewModel.onInit();
          async.flushMicrotasks();

          async.elapse(
            const Duration(seconds: OtpViewModel.resendCooldownSeconds),
          );

          viewModel.resendEmailOtp();
          async.flushMicrotasks();

          expect(facade.resendCount, 1);
          expect(viewModel.resendCooldown, OtpViewModel.resendCooldownSeconds);
          expect(viewModel.canResend, isFalse);
          viewModel.dispose();
        });
      });
    });
  });
}

const AuthSession _session = AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  userId: 'auth-user-1',
  email: 'tourist@example.com',
);

/// Fakes the logic facade - the only seam `OtpViewModel` knows.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  _FakeTouristInformationLogicFacade({
    this.pendingEmail = '',
    this.verifyResult,
    this.verifyError,
  });

  final String pendingEmail;
  final AuthSession? verifyResult;

  /// When set, [verifyEmailOtp] throws this instead of returning.
  final Object? verifyError;
  int resendCount = 0;

  @override
  String get pendingAuthEmail => pendingEmail;

  @override
  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }

  @override
  Future<bool> needsProfileSetup() async => false;

  @override
  Future<void> sendEmailOtp(String email) async {
    resendCount++;
  }
}
