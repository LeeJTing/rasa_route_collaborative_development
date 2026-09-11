import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';

LandmarkItem _item({String dish = 'Cendol', String variant = ''}) =>
    LandmarkItem(
      id: 1,
      landmarkId: 10,
      touristId: 'tourist-1',
      localFoodId: 375,
      dish: dish,
      variant: variant,
      foodCategory: 'Nyonya',
      description: '',
      origin: '',
      culturalBackground: '',
      seasonal: '',
      cookingStyle: '',
      mealType: '',
    );

void main() {
  group('LandmarkItem.displayName', () {
    test('a recorded variant is what the landmark shows', () {
      // The tourist captured "Cendol Jagung" - the landmark lists THAT, not
      // the dictionary dish it links to.
      expect(_item(variant: 'Cendol Jagung').displayName, 'Cendol Jagung');
      // Trimmed, so a stray space never makes the name look different.
      expect(_item(variant: '  Cendol Jagung  ').displayName, 'Cendol Jagung');
    });

    test('a blank variant falls back to the dictionary dish', () {
      expect(_item(variant: '').displayName, 'Cendol');
      expect(_item(variant: '   ').displayName, 'Cendol');
    });
  });
}
