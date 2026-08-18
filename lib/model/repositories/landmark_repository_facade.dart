import 'location_repository.dart';
import 'map_repository.dart';
import 'submitted_landmark_repository.dart';

/// Everything about places the tourist contributes and explores: submitted landmarks, the map viewport and the device location.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class LandmarkRepositoryFacade {
  LandmarkRepositoryFacade();

  final SubmittedLandmarkRepository landmark = SubmittedLandmarkRepository();
  final MapRepository map = MapRepository();
  final LocationRepository location = LocationRepository();
}
