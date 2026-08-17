import '../repositories/landmark_repository_facade.dart';

/// The dashboard map: where the tourist is and what is around them.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class MapExplorationLogic {
  MapExplorationLogic();

  final LandmarkRepositoryFacade repository = LandmarkRepositoryFacade();
}
