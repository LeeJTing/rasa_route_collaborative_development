import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/authenticate_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/tourist_repository_facade.dart';

void main() {
  group('AuthenticateLogic.emailError', () {
    test('accepts well-formed addresses', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(logic.emailError('tourist@example.com'), isNull);
      expect(logic.emailError('a@b.com'), isNull);
      expect(logic.emailError('first.last+tag@sub.example.co'), isNull);
      expect(logic.emailError('  padded@example.com  '), isNull);
    });

    test('does not impose a 30-char username cap (RFC allows up to 64)', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      // Longer than Gmail's 30-char sign-up limit, but valid per
      // RFC 5321/5322 - must be accepted.
      final String longUsername = 'a' * 40;
      expect(logic.emailError('$longUsername@example.com'), isNull);
      final String sixtyFour = 'b' * 64;
      expect(logic.emailError('$sixtyFour@example.com'), isNull);

      // 65 characters in the local part breaches the RFC 5321 ceiling.
      final String sixtyFive = 'c' * 65;
      expect(logic.emailError('$sixtyFive@example.com'), isNotNull);
    });

    test('rejects boundary failures', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      // Nothing before/after the @, no dot (so no TLD), one-letter TLD.
      expect(logic.emailError('username@'), isNotNull);
      expect(logic.emailError('@domain.com'), isNotNull);
      expect(logic.emailError('username@domain'), isNotNull);
      expect(logic.emailError('username@domain.c'), isNotNull);
    });

    test('rejects dot errors', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(logic.emailError('.user@domain.com'), isNotNull);
      expect(logic.emailError('user.@domain.com'), isNotNull);
      expect(logic.emailError('user..name@domain.com'), isNotNull);
      expect(logic.emailError('username@domain.'), isNotNull);
    });

    test('rejects formatting blunders', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(logic.emailError('user name@domain.com'), isNotNull);
      expect(logic.emailError('user@name@domain.com'), isNotNull);
    });

    test('rejects symbols providers ban in the local part', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(logic.emailError('!^&abc@gmail.com'), isNotNull);
      expect(logic.emailError('?abd@.com'), isNotNull);
    });

    test('returns null for a blank value (required, not malformed)', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(logic.emailError(''), isNull);
      expect(logic.emailError('   '), isNull);
    });

    test('names the specific problem, not a generic message', () {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(
        logic.emailError('user name@domain.com'),
        AuthenticateLogic.emailSpaceMessage,
      );
      expect(
        logic.emailError('user..name@domain.com'),
        AuthenticateLogic.emailDotMessage,
      );
      expect(
        logic.emailError('username@domain'),
        AuthenticateLogic.emailNoTldMessage,
      );
      expect(
        logic.emailError('username@domain.c'),
        AuthenticateLogic.emailTldBadMessage,
      );
      expect(
        logic.emailError('!^&abc@gmail.com'),
        AuthenticateLogic.emailInvalidCharMessage,
      );
      expect(
        logic.emailError('username@'),
        AuthenticateLogic.emailMissingDomainMessage,
      );
      expect(
        logic.emailError('@domain.com'),
        AuthenticateLogic.emailMissingNameMessage,
      );
      expect(
        logic.emailError('user@name@domain.com'),
        AuthenticateLogic.emailTooManyAtMessage,
      );
    });
  });

  group('AuthenticateLogic.sendEmailOtp', () {
    test('throws on an empty email', () async {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(() => logic.sendEmailOtp('   '), throwsArgumentError);
    });

    test(
      'refuses to send to a malformed address (never reaches Supabase)',
      () async {
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade();
        final AuthenticateLogic logic = AuthenticateLogic(
          repository: repository,
        );

        await expectLater(logic.sendEmailOtp('username@'), throwsArgumentError);
        await expectLater(
          logic.sendEmailOtp('user..name@domain.com'),
          throwsArgumentError,
        );

        expect(repository.sentEmails, isEmpty);
        expect(repository.recordedOtpSends, isEmpty);
      },
    );

    test('forwards the trimmed email to the repository', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      await logic.sendEmailOtp('  tourist@example.com  ');

      expect(repository.sentEmails, <String>['tourist@example.com']);
      expect(repository.recordedOtpSends, <String>['tourist@example.com']);
    });

    test('allows up to the rate limit of sends per window', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      for (int i = 0; i < AuthenticateLogic.otpSendRateLimit; i++) {
        await logic.sendEmailOtp('tourist@example.com');
      }

      expect(repository.sentEmails.length, AuthenticateLogic.otpSendRateLimit);
      expect(
        repository.recordedOtpSends.length,
        AuthenticateLogic.otpSendRateLimit,
      );
    });

    test(
      'rejects a send beyond the rate limit with the friendly message',
      () async {
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade();
        final AuthenticateLogic logic = AuthenticateLogic(
          repository: repository,
        );

        // Seed the stored history with the full quota inside the window.
        repository.otpSendTimesResult = List<DateTime>.generate(
          AuthenticateLogic.otpSendRateLimit,
          (_) => DateTime.now(),
        );

        await expectLater(
          logic.sendEmailOtp('tourist@example.com'),
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.message,
              'message',
              AuthenticateLogic.otpSendRateLimitMessage,
            ),
          ),
        );

        // A blocked send never reaches the repository.
        expect(repository.sentEmails, isEmpty);
      },
    );

    test('ignores sends older than the rate-limit window', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      // Old sends happened long before the window - they must not count.
      repository.otpSendTimesResult = List<DateTime>.generate(
        AuthenticateLogic.otpSendRateLimit,
        (_) => DateTime.now().subtract(
          AuthenticateLogic.otpSendRateWindow + const Duration(minutes: 1),
        ),
      );

      await logic.sendEmailOtp('tourist@example.com');

      expect(repository.sentEmails, <String>['tourist@example.com']);
    });

    test('does not record a send the repository rejected', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(throwOnSend: true);
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      await expectLater(
        logic.sendEmailOtp('tourist@example.com'),
        throwsStateError,
      );

      expect(repository.recordedOtpSends, isEmpty);
    });
  });

  group('AuthenticateLogic.verifyEmailOtp', () {
    test('throws on an empty email', () async {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(
        () => logic.verifyEmailOtp(email: '  ', token: '123456'),
        throwsArgumentError,
      );
    });

    test('throws on an empty token', () async {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(
        () => logic.verifyEmailOtp(email: 'a@b.com', token: ' '),
        throwsArgumentError,
      );
    });

    test('auto-creates the tourist row when verification succeeds', () async {
      final AuthSession session = _session();
      final Tourist tourist = _tourist();
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(
            verifyResult: session,
            touristResult: tourist,
          );
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      final AuthSession? result = await logic.verifyEmailOtp(
        email: '  tourist@example.com  ',
        token: '  123456 ',
      );

      expect(result, same(session));
      expect(repository.verifyCalls, <String>['tourist@example.com']);
      expect(repository.provisionedSessions, <AuthSession>[session]);
    });

    test('does not provision a tourist when verification fails', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(verifyResult: null);
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      final AuthSession? result = await logic.verifyEmailOtp(
        email: 'a@b.com',
        token: '123456',
      );

      expect(result, isNull);
      expect(repository.provisionedSessions, isEmpty);
    });
  });

  group('AuthenticateLogic.completeGoogleSignIn', () {
    test('resolves the session and provisions the tourist row', () async {
      final AuthSession session = _session();
      final Tourist tourist = _tourist();
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(
            currentSession: session,
            touristResult: tourist,
          );
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      final Tourist? result = await logic.completeGoogleSignIn();

      expect(result, same(tourist));
      expect(repository.provisionedSessions, <AuthSession>[session]);
    });

    test('returns null when no session was established', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(currentSession: null);
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      final Tourist? result = await logic.completeGoogleSignIn();

      expect(result, isNull);
      expect(repository.provisionedSessions, isEmpty);
    });
  });
}

AuthSession _session() => const AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  userId: 'auth-user-1',
  email: 'tourist@example.com',
);

Tourist _tourist() => Tourist(
  touristId: '11111111-1111-4111-8111-111111111111',
  authUserId: 'auth-user-1',
  email: 'tourist@example.com',
  displayName: '',
);

/// Fakes the repository facade - the only seam `AuthenticateLogic` knows.
class _FakeTouristRepositoryFacade extends TouristRepositoryFacade {
  _FakeTouristRepositoryFacade({
    this.verifyResult,
    this.currentSession,
    this.touristResult,
    this.throwOnSend = false,
  });

  AuthSession? verifyResult;
  AuthSession? currentSession;
  Tourist? touristResult;

  /// When true, [sendEmailOtp] throws before recording (a rejected address).
  bool throwOnSend;

  /// Pre-seeded OTP send history returned by [otpSendTimes].
  List<DateTime> otpSendTimesResult = const <DateTime>[];

  final List<String> sentEmails = <String>[];
  final List<String> verifyCalls = <String>[];
  final List<AuthSession> provisionedSessions = <AuthSession>[];
  final List<String> recordedOtpSends = <String>[];

  @override
  Future<void> sendEmailOtp(String email) async {
    if (throwOnSend) {
      throw StateError('Unable to send the code.');
    }
    sentEmails.add(email);
  }

  @override
  Future<List<DateTime>> otpSendTimes(String email) async => otpSendTimesResult;

  @override
  Future<void> recordOtpSend(String email) async {
    recordedOtpSends.add(email);
  }

  @override
  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifyCalls.add(email);
    return verifyResult;
  }

  @override
  Future<AuthSession?> getCurrentSession() async => currentSession;

  @override
  Future<Tourist?> getOrCreateTourist(AuthSession session) async {
    provisionedSessions.add(session);
    return touristResult;
  }
}
