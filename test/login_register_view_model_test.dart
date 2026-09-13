import 'package:flutter_test/flutter_test.dart';
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

    test('onInit flags needsProfileSetup for a new tourist', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          session: const AuthSession(
            accessToken: 'a',
            refreshToken: 'r',
            userId: 'auth-1',
            email: 'tourist@example.com',
          ),
          needsProfileSetupResult: true,
        ),
      );

      await viewModel.onInit();

      expect(viewModel.signedIn, isTrue);
      expect(viewModel.needsProfileSetup, isTrue);
    });

    test('completeGoogleSignIn picks up needsProfileSetup', () async {
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          googleCompleteResult: _tourist(),
          needsProfileSetupResult: true,
        ),
      );

      await viewModel.completeGoogleSignIn();

      expect(viewModel.googleSignInComplete, isTrue);
      expect(viewModel.needsProfileSetup, isTrue);
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
      'completeGoogleSignIn waits for a late session instead of erroring',
      () async {
        // The Supabase SDK finishes the PKCE code exchange a moment after the
        // app resumes, so the first facade call can legitimately return null.
        final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            googleCompleteResult: _tourist(),
            nullResultsBeforeSuccess: 2,
          ),
          googleSessionGracePeriod: const Duration(milliseconds: 300),
          googleSessionRetryInterval: const Duration(milliseconds: 5),
        );

        await viewModel.completeGoogleSignIn();

        expect(viewModel.googleSignInComplete, isTrue);
        expect(viewModel.hasError, isFalse);
      },
    );

    test(
      'completeGoogleSignIn reports an error when no session resolved',
      () async {
        final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            googleCompleteResult: null,
          ),
          // No session ever arrives - do not actually wait the real 5s grace
          // window in a unit test.
          googleSessionGracePeriod: Duration.zero,
        );

        await viewModel.completeGoogleSignIn();

        expect(viewModel.googleSignInComplete, isFalse);
        expect(viewModel.hasError, isTrue);
      },
    );

    test('an abandoned flow stops being retried on every app resume', () async {
      // Regression: `googleFlowStarted` was never cleared, and the View resumes
      // on it - so tapping Continue with Google, coming back from the browser
      // without signing in, then switching apps at any point afterwards re-ran
      // the whole grace-period poll and re-showed the failure, every single
      // time, for the rest of the session.
      final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          googleCompleteResult: null,
        ),
        googleSessionGracePeriod: Duration.zero,
      );

      await viewModel.signInWithGoogle();
      expect(viewModel.googleFlowStarted, isTrue);

      await viewModel.completeGoogleSignIn();

      // The View's guard is `googleFlowStarted && !googleSignInComplete`, so
      // this is what stops the loop.
      expect(viewModel.googleFlowStarted, isFalse);
      expect(viewModel.googleSignInComplete, isFalse);
    });

    test(
      'a successful flow still reports complete after the marker clears',
      () async {
        // Clearing the marker must not cost the View its navigation: it reads
        // `googleSignInComplete` straight after this call.
        final LoginRegisterViewModel viewModel = LoginRegisterViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            googleCompleteResult: _tourist(),
          ),
          googleSessionGracePeriod: Duration.zero,
        );

        await viewModel.signInWithGoogle();
        await viewModel.completeGoogleSignIn();

        expect(viewModel.googleSignInComplete, isTrue);
        expect(viewModel.googleFlowStarted, isFalse);
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
    this.nullResultsBeforeSuccess = 0,
    this.session,
    this.needsProfileSetupResult = false,
  });

  final bool googleStartResult;
  final Tourist? googleCompleteResult;

  /// How many initial [completeGoogleSignIn] calls return null before
  /// [googleCompleteResult] is returned - models the Supabase SDK still
  /// exchanging the PKCE code when the app resumes.
  final int nullResultsBeforeSuccess;
  final AuthSession? session;
  final bool needsProfileSetupResult;

  int googleCompleteCalls = 0;

  @override
  Future<AuthSession?> getCurrentSession() async => session;

  @override
  Future<bool> signInWithGoogle({required String redirectTo}) async {
    return googleStartResult;
  }

  @override
  Future<Tourist?> completeGoogleSignIn() async {
    googleCompleteCalls++;
    if (googleCompleteCalls <= nullResultsBeforeSuccess) return null;
    return googleCompleteResult;
  }

  @override
  Future<bool> needsProfileSetup() async => needsProfileSetupResult;
}
