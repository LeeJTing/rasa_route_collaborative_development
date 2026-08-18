import '../repositories/tourist_repository_facade.dart';

/// Sign-in, sign-up and OTP rules.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class AuthenticateLogic {
  AuthenticateLogic();

  final TouristRepositoryFacade repository = TouristRepositoryFacade();
}
