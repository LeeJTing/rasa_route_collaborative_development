/// Temporary hand-off for navigation to a submitted-landmark detail screen.
///
/// Routes currently pass no arguments and ViewModels take no constructor
/// parameters, so a caller stores the selected `submitted_landmark.landmark_id`
/// immediately before navigation. The destination reads and clears it during
/// initialisation.
class MapSelectionHandoff {
  factory MapSelectionHandoff() => _instance;

  MapSelectionHandoff._();

  static final MapSelectionHandoff _instance = MapSelectionHandoff._();

  /// The `submitted_landmark.landmark_id` behind the selected landmark.
  int? pendingLandmarkId;

  int? takeLandmarkId() {
    final int? value = pendingLandmarkId;
    pendingLandmarkId = null;
    return value;
  }
}
