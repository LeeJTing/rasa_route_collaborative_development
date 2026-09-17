import 'submitted_landmark_repository.dart';
import '../../domain_model/submitted_landmark.dart';

/// Discovery-owned read access to submitted landmarks.
///
/// Landmark creation and correction remain behind the Landmark module. This
/// repository exposes only the read needed by map and recommendation details.
/// It is a narrow read adapter, not an inherited alias for the full submission
/// repository API.
class LandmarkDiscoveryRepository {
  final SubmittedLandmarkRepository _source = SubmittedLandmarkRepository();

  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) =>
      _source.getSubmittedLandmarkById(landmarkId);
}
