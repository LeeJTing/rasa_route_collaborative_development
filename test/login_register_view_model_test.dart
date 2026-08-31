import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/login_register_view_model.dart';

void main() {
  group('LoginRegisterViewModel', () {
    test('onInit marks signedIn when a session is restored', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          session: const AuthSession(
            accessToken: 'a',
            refreshToken: 'r',
            userId: 'auth-1',
            email: 'tourist@example.com',
          ),
        ),
      );

      await viewModel.onInit();

      expect(viewModel.checkingSession, isFalse);
      expect(viewModel.signedIn, isTrue);
    });

    test('onInit leaves signedIn false when no session exists', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );

      await viewModel.onInit();

      expect(viewModel.checkingSession, isFalse);
      expect(viewModel.signedIn, isFalse);
    });

    test('canSendOtp requires a non-empty email', () {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );

      expect(viewModel.canSendOtp, isFalse);

      viewModel.setEmail('  ');

      expect(viewModel.canSendOtp, isFalse);

      viewModel.setEmail('a@b.com');

      expect(viewModel.canSendOtp, isTrue);
    });

    test('setEmail notifies listeners', () {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );
      int notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.setEmail('a@b.com');

      expect(notifications, greaterThan(0));
      expect(viewModel.email, 'a@b.com');
    });

    test('sendEmailOtp marks otpSent on success', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );
      viewModel.setEmail('a@b.com');

      await viewModel.sendEmailOtp();

      expect(viewModel.otpSent, isTrue);
      expect(viewModel.state, ViewState.ready);
    });

    test('sendEmailOtp surfaces an error without marking otpSent', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(throwOnSendOtp: true),
      );
      viewModel.setEmail('a@b.com');

      await viewModel.sendEmailOtp();

      expect(viewModel.otpSent, isFalse);
      expect(viewModel.hasError, isTrue);
    });

    test('signInWithGoogle records a started flow', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );

      await viewModel.signInWithGoogle();

      expect(viewModel.googleFlowStarted, isTrue);
      expect(viewModel.hasError, isFalse);
    });

    test(
      'signInWithGoogle reports an error when the flow cannot start',
      () async {
        final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            googleStartResult: false,
          ),
        );

        await viewModel.signInWithGoogle();

        expect(viewModel.googleFlowStarted, isFalse);
        expect(viewModel.hasError, isTrue);
      },
    );

    test('completeGoogleSignIn marks the sign-in complete', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          googleCompleteResult: _tourist(),
        ),
      );

      await viewModel.completeGoogleSignIn();

      expect(viewModel.googleSignInComplete, isTrue);
      expect(viewModel.hasError, isFalse);
    });

    test(
      'completeGoogleSignIn reports an error when no session resolved',
      () async {
        final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            googleCompleteResult: null,
          ),
        );

        await viewModel.completeGoogleSignIn();

        expect(viewModel.googleSignInComplete, isFalse);
        expect(viewModel.hasError, isTrue);
      },
    );
  });
}

Tourist _tourist() => Tourist(
  touristId: '11111111-1111-4111-8111-111111111111',
  authUserId: 'auth-user-1',
  email: 'tourist@example.com',
  displayName: '',
);

/// Fakes the logic facade - the only seam `LoginRegisterViewModel` knows.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  _FakeTouristInformationLogicFacade({
    this.googleStartResult = true,
    this.googleCompleteResult,
    this.throwOnSendOtp = false,
    this.session,
  });

  final bool googleStartResult;
  final Tourist? googleCompleteResult;
  bool throwOnSendOtp;
  final AuthSession? session;

  @override
  Future<AuthSession?> getCurrentSession() async => session;

  @override
  Future<void> sendEmailOtp(String email) async {
    if (throwOnSendOtp) throw StateError('send OTP failed');
  }

  @override
  Future<bool> signInWithGoogle({required String redirectTo}) async {
    return googleStartResult;
  }

  @override
  Future<Tourist?> completeGoogleSignIn() async {
    return googleCompleteResult;
  }
}
