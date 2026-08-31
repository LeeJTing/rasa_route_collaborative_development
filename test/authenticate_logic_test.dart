import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/authenticate_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/tourist_repository_facade.dart';

void main() {
  group('AuthenticateLogic.sendEmailOtp', () {
    test('throws on an empty email', () async {
      final AuthenticateLogic logic = AuthenticateLogic(
        repository: _FakeTouristRepositoryFacade(),
      );

      expect(() => logic.sendEmailOtp('   '), throwsArgumentError);
    });

    test('forwards the trimmed email to the repository', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();
      final AuthenticateLogic logic = AuthenticateLogic(repository: repository);

      await logic.sendEmailOtp('  tourist@example.com  ');

      expect(repository.sentEmails, <String>['tourist@example.com']);
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
  });

  AuthSession? verifyResult;
  AuthSession? currentSession;
  Tourist? touristResult;

  final List<String> sentEmails = <String>[];
  final List<String> verifyCalls = <String>[];
  final List<AuthSession> provisionedSessions = <AuthSession>[];

  @override
  Future<void> sendEmailOtp(String email) async {
    sentEmails.add(email);
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
