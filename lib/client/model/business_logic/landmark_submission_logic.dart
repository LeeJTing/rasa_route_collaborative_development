import '../facades/landmark_logic_facade.dart';
import '../../repositories/facades/location_repository.dart';
import '../../repositories/facades/recognition_repository.dart';

class LandmarkSubmissionLogic implements LandmarkLogicFacade {
  final LocationRepository locationRepository;
  final RecognitionRepository recognitionRepository;

  LandmarkSubmissionLogic({
    required this.locationRepository,
    required this.recognitionRepository,
  });

  // TODO: Implement LandmarkSubmissionLogic by coordinating repository facades only.
}
