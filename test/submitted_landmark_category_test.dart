import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';

/// A landmark's dishes can disagree about their food category, and the
/// category the tourist is shown is the one MOST of the dishes carry (user
/// request, 2026-09-13) - the stored `submitted_landmark.category` only
/// exists because a submission has to name one, so it can easily be the
/// minority once more dishes are added.
LandmarkItem _dish({required String dish, String foodCategory = ''}) =>
    LandmarkItem(
      id: dish.length,
      landmarkId: 7,
      touristId: 'tourist-1',
      dish: dish,
      variant: '',
      foodCategory: foodCategory,
      description: '',
      origin: '',
      culturalBackground: '',
      seasonal: '',
      cookingStyle: '',
      mealType: '',
    );

SubmittedLandmark _landmark({
  String category = '',
  List<LandmarkItem> items = const <LandmarkItem>[],
}) => SubmittedLandmark(
  id: 7,
  name: 'HOMETOWN ICE KACANG',
  latitude: 3.1,
  longitude: 101.6,
  category: category,
  reportedCount: 0,
  status: LandmarkStatus.available,
  items: items,
  openingHours: const <OpeningHour>[],
);

void main() {
  test('the category most of the dishes carry wins over the submitted one', () {
    final SubmittedLandmark landmark = _landmark(
      category: 'Malay',
      items: <LandmarkItem>[
        _dish(dish: 'Wan Tan Mee', foodCategory: 'Chinese'),
        _dish(dish: 'Char Kuey Teow', foodCategory: 'Chinese'),
        _dish(dish: 'Nasi Lemak', foodCategory: 'Malay'),
      ],
    );

    expect(landmark.displayCategory, 'Chinese');
  });

  test('a tie keeps the category of the first dish that has one', () {
    final SubmittedLandmark landmark = _landmark(
      category: 'Malay',
      items: <LandmarkItem>[
        _dish(dish: 'Wan Tan Mee', foodCategory: 'Chinese'),
        _dish(dish: 'Nasi Lemak', foodCategory: 'Malay'),
      ],
    );

    expect(landmark.displayCategory, 'Chinese');
  });

  test('dishes with no category fall back to the submitted one', () {
    final SubmittedLandmark landmark = _landmark(
      category: 'Malay',
      items: <LandmarkItem>[
        _dish(dish: 'Ice Kacang'),
        _dish(dish: 'Cendol', foodCategory: '   '),
      ],
    );

    expect(landmark.displayCategory, 'Malay');
  });

  test('nothing on record is empty, never invented text', () {
    expect(_landmark().displayCategory, '');
    expect(
      _landmark(
        items: <LandmarkItem>[_dish(dish: 'Ice Kacang')],
      ).displayCategory,
      '',
    );
  });

  test('the label reads like the restaurant table stores it', () {
    final SubmittedLandmark landmark = _landmark(
      items: <LandmarkItem>[
        _dish(dish: 'Wan Tan Mee', foodCategory: 'Chinese'),
      ],
    );

    expect(landmark.displayCategoryLabel, 'Chinese restaurant');
  });

  test('a category that already says restaurant is left alone', () {
    final SubmittedLandmark landmark = _landmark(
      items: <LandmarkItem>[
        _dish(dish: 'Wan Tan Mee', foodCategory: 'Chinese restaurant'),
      ],
    );

    expect(landmark.displayCategoryLabel, 'Chinese restaurant');
  });

  test('an unknown category stays empty rather than inventing a suffix', () {
    expect(_landmark().displayCategoryLabel, '');
  });
}
