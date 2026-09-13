import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/otp_view_model.dart';

void main() {
  group('OtpViewModel onInit - email resolution', () {
    test('uses the email from the route argument', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );
      addTearDown(viewModel.dispose);
      viewModel.emailArgument = 'a@b.com';

      await viewModel.onInit();

      expect(viewModel.email, 'a@b.com');
      expect(viewModel.hasError, isFalse);
    });

    test(
      'falls back to the pending email when no argument is supplied',
      () async {
        final OtpViewModel viewModel = OtpViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            pendingEmail: 'a@b.com',
          ),
        );
        addTearDown(viewModel.dispose);

        await viewModel.onInit();

        expect(viewModel.email, 'a@b.com');
        expect(viewModel.hasError, isFalse);
      },
    );

    test('onInit reports an error when no email is pending', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(),
      );
      addTearDown(viewModel.dispose);

      await viewModel.onInit();

      expect(viewModel.hasError, isTrue);
    });
  });

  group('OtpViewModel send decision', () {
    test('sends a fresh code on first entry (no pending code)', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(pendingEmail: 'a@b.com');
      final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
      addTearDown(viewModel.dispose);

      await viewModel.onInit();

      expect(facade.sendCount, 1);
      expect(viewModel.hasError, isFalse);
      expect(viewModel.state, ViewState.ready);
    });

    test(
      'does not re-send when a valid pending code is still within its window',
      () async {
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade(
              pendingEmail: 'a@b.com',
              pendingOtpSentAtOverride: DateTime.now(),
            );
        final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
        addTearDown(viewModel.dispose);

        await viewModel.onInit();

        expect(facade.sendCount, 0);
        expect(viewModel.hasError, isFalse);
      },
    );

    test('sends a fresh code when the pending code has expired', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            pendingEmail: 'a@b.com',
            pendingOtpSentAtOverride: DateTime.now().subtract(
              const Duration(hours: 2),
            ),
          );
      final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
      addTearDown(viewModel.dispose);

      await viewModel.onInit();

      expect(facade.sendCount, 1);
    });

    test('sends a fresh code when the pending email does not match', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            pendingEmail: 'someone-else@x.com',
            pendingOtpSentAtOverride: DateTime.now(),
          );
      final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
      addTearDown(viewModel.dispose);
      viewModel.emailArgument = 'a@b.com';

      await viewModel.onInit();

      expect(viewModel.email, 'a@b.com');
      expect(facade.sendCount, 1);
    });

    test('surfaces a 3-per-10 gate error on entry send', () async {
      final OtpViewModel viewModel = OtpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(
          pendingEmail: 'a@b.com',
          throwOnSend: true,
        ),
      );
      addTearDown(viewModel.dispose);

      await viewModel.onInit();

      expect(viewModel.hasError, isTrue);
      expect(
        viewModel.errorMessage,
        'Too many attempts, please try again later.',
      );
    });

    test(
      'reusing an existing code is exposed so the View can hint at it',
      () async {
        // The server already emailed a code for this address - the screen must
        // not pretend a fresh code is on its way.
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade(
              pendingEmail: 'a@b.com',
              pendingOtpSentAtOverride: DateTime.now().subtract(
                const Duration(seconds: 10),
              ),
            );
        final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
        addTearDown(viewModel.dispose);

        await viewModel.onInit();

        expect(facade.sendCount, 0);
        expect(viewModel.hasError, isFalse);
        expect(viewModel.reusingExistingCode, isTrue);
      },
    );

    test('over-limit resend shows the message and is not a silent no-op', () {
      fakeAsync((FakeAsync async) {
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade(
              pendingEmail: 'a@b.com',
              pendingOtpSentAtOverride: DateTime.now().subtract(
                const Duration(seconds: 10),
              ),
            );
        final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
        viewModel.onInit();
        async.flushMicrotasks();

        // Reuse path resumes ~50s. Once that ends, the next resend is over the
        // 3-per-10 gate and is rejected.
        facade.throwOnSend = true;
        async.elapse(const Duration(seconds: 60));

        viewModel.resendEmailOtp();
        async.flushMicrotasks();

        // The rejection is never swallowed: the tourist sees why it failed...
        expect(viewModel.hasError, isTrue);
        expect(
          viewModel.errorMessage,
          'Too many attempts, please try again later.',
        );
        // ...still learns the earlier code is usable...
        expect(viewModel.reusingExistingCode, isTrue);
        // ...and the cooldown runs so the button cannot be hammered silently.
        expect(viewModel.canResend, isFalse);
        expect(viewModel.resendCooldown, greaterThan(0));
        viewModel.dispose();
      });
    });

    test(
      'an unresolvable send error leaves the message but not a spammable button',
      () {
        fakeAsync((FakeAsync async) {
          final _FakeTouristInformationLogicFacade facade =
              _FakeTouristInformationLogicFacade(
                pendingEmail: 'a@b.com',
                throwOnSend: true,
              );
          final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
          viewModel.onInit();
          async.flushMicrotasks();

          // No reusable code exists, so the error stays - but the cooldown now
          // runs so the Resend control cannot be hammered.
          expect(viewModel.hasError, isTrue);
          expect(viewModel.canResend, isFalse);
          viewModel.dispose();
        });
      },
    );
  });

  group('OtpViewModel token & verify', () {
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

    test(
      'isVerifying is true in flight and false after a rejected code',
      () async {
        final OtpViewModel viewModel = OtpViewModel(
          touristLogic: _FakeTouristInformationLogicFacade(
            pendingEmail: 'a@b.com',
            verifyResult: null,
          ),
        );
        addTearDown(viewModel.dispose);
        await viewModel.onInit();
        viewModel.setToken('123456');

        // Not awaited yet on purpose: the flag is raised synchronously, so the
        // View locks the boxes on the first frame of the request rather than
        // one pump later.
        final Future<void> inFlight = viewModel.verifyEmailOtp();
        expect(viewModel.isVerifying, isTrue);

        await inFlight;

        // A rejected code unlocks the boxes, so the digits can be corrected.
        expect(viewModel.verified, isFalse);
        expect(viewModel.isVerifying, isFalse);
      },
    );

    test(
      'isVerifying stays true after a success so the boxes stay locked',
      () async {
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
        // The View is navigating away; unlocking here would reopen the window
        // where a backspace de-syncs the screen from the completed request.
        expect(viewModel.isVerifying, isTrue);
      },
    );

    test('a second submit in flight never reaches the backend twice', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            pendingEmail: 'a@b.com',
            verifyResult: _session,
          );
      final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
      addTearDown(viewModel.dispose);
      await viewModel.onInit();
      viewModel.setToken('123456');

      final Future<void> first = viewModel.verifyEmailOtp();
      await viewModel.verifyEmailOtp();
      await first;

      expect(facade.verifyCount, 1);
    });
  });

  group('resend countdown', () {
    test('starts at 60 seconds and counts down to zero after a fresh send', () {
      fakeAsync((FakeAsync async) {
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade(pendingEmail: 'a@b.com');
        final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
        viewModel.onInit();
        async.flushMicrotasks();

        expect(facade.sendCount, 1);
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

    test('resumes the remaining countdown when reusing a pending code', () {
      fakeAsync((FakeAsync async) {
        // Sent 10s ago: 50s of the 60s resend window remain.
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade(
              pendingEmail: 'a@b.com',
              pendingOtpSentAtOverride: DateTime.now().subtract(
                const Duration(seconds: 10),
              ),
            );
        final OtpViewModel viewModel = OtpViewModel(touristLogic: facade);
        viewModel.onInit();
        async.flushMicrotasks();

        expect(facade.sendCount, 0);
        // ~10s already elapsed of the 60s window - allow a little drift.
        expect(viewModel.resendCooldown, inInclusiveRange(48, 50));
        expect(viewModel.canResend, isFalse);

        async.elapse(const Duration(seconds: 50));

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

        // onInit already sent the first code; the blocked resend adds none.
        expect(facade.sendCount, 1);
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

        expect(facade.sendCount, 2); // first entry send + resend
        expect(viewModel.resendCooldown, OtpViewModel.resendCooldownSeconds);
        expect(viewModel.canResend, isFalse);
        viewModel.dispose();
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
    this.pendingOtpSentAtOverride,
    this.verifyResult,
    this.verifyError,
    this.throwOnSend = false,
  });

  final String pendingEmail;
  final DateTime? pendingOtpSentAtOverride;
  final AuthSession? verifyResult;

  /// When set, [verifyEmailOtp] throws this instead of returning.
  final Object? verifyError;

  /// When set, [sendEmailOtp] throws the 3-per-10 gate error. Mutable so a
  /// test can flip behaviour mid-flow.
  bool throwOnSend;
  int sendCount = 0;
  int verifyCount = 0;

  @override
  String get pendingAuthEmail => pendingEmail;

  @override
  DateTime? get pendingOtpSentAt => pendingOtpSentAtOverride;

  @override
  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifyCount++;
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }

  @override
  Future<bool> needsProfileSetup() async => false;

  @override
  Future<void> sendEmailOtp(String email) async {
    if (throwOnSend) {
      throw StateError('Too many attempts, please try again later.');
    }
    sendCount++;
  }
}
