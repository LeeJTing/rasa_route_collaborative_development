import '../repositories/tourist_repository_facade.dart';

/// Profile set-up and preference management.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class UserProfileLogic {
  UserProfileLogic();

  final TouristRepositoryFacade repository = TouristRepositoryFacade();
}
