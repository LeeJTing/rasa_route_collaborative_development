import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

/// Manual food-name entry rule: typing stops at 50 characters, and from 45
/// the tourist is warned to keep the dish name short. Lives in
/// `LandmarkSubmissionLogic` so both recognition name fields (single result
/// + multiple results) show the identical message.
void main() {
  final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

  group('foodNameLengthWarning', () {
    test('a normal-length name has no warning', () {
      expect(logic.foodNameLengthWarning('Murtabak'), isNull);
      expect(logic.foodNameLengthWarning('a' * 44), isNull);
    });

    test('the warning starts at 45 characters and names the cap', () {
      final String? warning = logic.foodNameLengthWarning('a' * 45);

      expect(warning, isNotNull);
      expect(warning, contains('50 characters'));
      expect(warning, contains('45'));
    });

    test(
      'the warning counts the TRIMMED value (stray spaces do not trip it)',
      () {
        expect(logic.foodNameLengthWarning('${'a' * 44}   '), isNull);
        expect(logic.foodNameLengthWarning('  ${'a' * 45}  '), isNotNull);
      },
    );

    test('the caps stay aligned (50 max / 45 warn)', () {
      expect(LandmarkSubmissionLogic.maxFoodNameLength, 50);
      expect(LandmarkSubmissionLogic.foodNameWarnFromLength, 45);
    });
  });
}
