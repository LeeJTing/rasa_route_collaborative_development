import '../repositories/landmark_repository_facade.dart';

/// Submitting a new food landmark and attaching dishes to it.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class LandmarkSubmissionLogic {
  LandmarkSubmissionLogic();

  final LandmarkRepositoryFacade repository = LandmarkRepositoryFacade();
}
