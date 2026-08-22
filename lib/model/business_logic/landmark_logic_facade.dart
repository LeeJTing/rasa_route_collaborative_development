import 'food_recognition_logic.dart';
import 'landmark_submission_logic.dart';
import 'map_exploration_logic.dart';

/// Contributing a food landmark - recognising the dish, capturing the
/// restaurant, submitting it - and exploring the map. Used by the
/// FoodRecognition, LandmarkDetail, AddLandmark, LandmarkHistory and
/// Dashboard ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class LandmarkLogicFacade {
  LandmarkLogicFacade();

  final FoodRecognitionLogic foodRecognition = FoodRecognitionLogic();
  final LandmarkSubmissionLogic submission = LandmarkSubmissionLogic();
  final MapExplorationLogic exploration = MapExplorationLogic();
}
