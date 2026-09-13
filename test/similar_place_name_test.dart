import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

/// The NAME pre-filter behind the near-duplicate place check: which two names
/// are close enough (>= 80%, see
/// `LandmarkSubmissionLogic.similarPlaceNameThreshold`) to be worth a photo
/// comparison (see `LandmarkSubmissionLogic.similarNearbyPlaces`).
void main() {
  group('placeNameSimilarity / namesLookSimilar (the 80% rule)', () {
    test('the same name scores 1, whatever the case or punctuation', () {
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Tian Yi', 'TIAN YI'),
        isTrue,
      );
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Ali & Abu', 'Ali and Abu'),
        isTrue,
      );
      // Generic shop words are dropped from the key first, so both sides are
      // just "ali".
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Restoran Ali', 'Kedai Ali'),
        isTrue,
      );
      expect(LandmarkSubmissionLogic.placeNameSimilarity('海天樓', '海天楼'), 1.0);
    });

    test('one name inside the other is the same shop extended', () {
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Tian Yi', 'Tian Yi Seafood'),
        isTrue,
      );
      expect(
        LandmarkSubmissionLogic.namesLookSimilar(
          'Restoran Ali',
          'Restoran Ali 2',
        ),
        isTrue,
      );
      // Chinese has no spaces to split on - containment is what catches a
      // name extended.
      expect(LandmarkSubmissionLogic.placeNameSimilarity('海天樓', '海天楼海鲜'), 1.0);
    });

    test('a near miss above 80% still qualifies', () {
      // A plural or a small typo on a long name is the same sign with new
      // paint: "Ali Baba" / "Ali Babas".
      final double score = LandmarkSubmissionLogic.placeNameSimilarity(
        'Restoran Ali Baba',
        'Restoran Ali Babas',
      );

      expect(score, greaterThanOrEqualTo(0.8));
      expect(
        LandmarkSubmissionLogic.namesLookSimilar(
          'Restoran Ali Baba',
          'Restoran Ali Babas',
        ),
        isTrue,
      );
      // "Tian Yi" vs "Tien Yi" - ONE letter of seven (0.857), still a match.
      expect(
        LandmarkSubmissionLogic.placeNameSimilarity('Tian Yi', 'Tien Yi'),
        closeTo(1 - 1 / 7, 0.001),
      );
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Tian Yi', 'Tien Yi'),
        isTrue,
      );
    });

    test('sharing one word is NOT enough - 80% of the name is', () {
      // These two share "Sushi"; under the old shared-word rule they reached
      // the photo question. They are different shops, and the 80% rule keeps
      // them apart.
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Sushi King', 'Sushi Tei'),
        isFalse,
      );
      expect(
        LandmarkSubmissionLogic.namesLookSimilar(
          'Nasi Lemak Gajah',
          'Nasi Lemak Pelita',
        ),
        isFalse,
      );
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Restoran Ali', 'Kedai Abu'),
        isFalse,
      );
    });

    test('different Chinese names never match', () {
      expect(LandmarkSubmissionLogic.namesLookSimilar('海天樓', '好味麵家'), isFalse);
    });

    test('an empty or generic-only side never matches', () {
      expect(LandmarkSubmissionLogic.placeNameSimilarity('', 'Ali'), 0);
      expect(
        LandmarkSubmissionLogic.namesLookSimilar('Restoran', 'Ali'),
        isFalse,
      );
      // A name of generic words only compares on its whole folded form, so
      // "Restoran" is not "Kedai" (both are just shop words).
      expect(
        LandmarkSubmissionLogic.placeNameSimilarity('Restoran', 'Kedai'),
        lessThan(LandmarkSubmissionLogic.similarPlaceNameThreshold),
      );
    });
  });
}
