import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

/// The NAME pre-filter behind the near-duplicate place check: which two names
/// are close enough to be worth a photo comparison (see
/// `LandmarkSubmissionLogic.similarNearbyPlaces`).
void main() {
  group('sharesSignificantNameWord', () {
    test('names that differ only by "&" / "and" qualify', () {
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord(
          'Ali & Abu',
          'Ali and Abu',
        ),
        isTrue,
      );
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord(
          'Restoran Ali & Abu',
          'ali abu',
        ),
        isTrue,
      );
    });

    test('sharing only a GENERIC word does not qualify', () {
      // "Restoran" and "Kedai" are on every other sign - they say nothing
      // about which shop it is.
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord(
          'Restoran Ali',
          'Kedai Abu',
        ),
        isFalse,
      );
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord(
          'Restoran Makanan',
          'Kedai Makanan',
        ),
        isFalse,
      );
    });

    test('a Chinese name folds, and an extended one still shares its word', () {
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord('海天樓', '海天楼'),
        isTrue,
      );
      // No spaces to split on, so a name that CONTAINS the other's word is
      // the same shop's name extended.
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord('海天樓', '海天楼海鲜'),
        isTrue,
      );
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord('海天樓', '好味麵家'),
        isFalse,
      );
    });

    test('an empty or generic-only side never matches', () {
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord('', 'Ali'),
        isFalse,
      );
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord('Restoran', 'Ali'),
        isFalse,
      );
    });

    test('a numbered second branch of the same name still qualifies', () {
      expect(
        LandmarkSubmissionLogic.sharesSignificantNameWord(
          'Restoran Ali',
          'Restoran Ali 2',
        ),
        isTrue,
      );
    });
  });
}
