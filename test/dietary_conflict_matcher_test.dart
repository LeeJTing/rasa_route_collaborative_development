import 'package:flutter_test/flutter_test.dart';

import 'package:rasa_route_collaborative_development/model/business_logic/food_recognition_logic.dart';

/// Pure matcher tests for `FoodRecognitionLogic.dietaryConflicts` - the
/// tolerant, case/substring-insensitive name matching that decides whether a
/// recognised dish's tags conflict with the signed-in tourist's saved
/// dietary restrictions (warning only; never blocking).
void main() {
  group('FoodRecognitionLogic.dietaryConflicts', () {
    test('matches an exact restriction name against a dish tag', () {
      final List<String> conflicts = FoodRecognitionLogic.dietaryConflicts(
        userRestrictions: const <String>['No Pork'],
        foodTags: const <String>['No Pork'],
      );
      expect(conflicts, <String>['No Pork']);
    });

    test('is case- and whitespace-insensitive', () {
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>['  no PORK '],
          foodTags: const <String>['no   pork'],
        ),
        <String>['  no PORK '], // returns the user's own wording
      );
    });

    test('flags a substring hit like "pork" inside "No Pork"', () {
      final List<String> conflicts = FoodRecognitionLogic.dietaryConflicts(
        userRestrictions: const <String>['No Pork'],
        foodTags: const <String>['pork'],
      );
      expect(conflicts, <String>['No Pork']);
    });

    test('flags a Gemini-style compound tag against the restriction', () {
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>['Halal'],
          foodTags: const <String>['Halal Certified'],
        ),
        <String>['Halal'],
      );
    });

    test('returns the user restriction wording, not the dish tag', () {
      final List<String> conflicts = FoodRecognitionLogic.dietaryConflicts(
        userRestrictions: const <String>['Pork-Free Diet'],
        foodTags: const <String>['Pork'],
      );
      expect(conflicts, <String>['Pork-Free Diet']);
    });

    test('no conflict when nothing overlaps', () {
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>['No Beef', 'Vegetarian'],
          foodTags: const <String>['No Pork', 'High Calorie'],
        ),
        isEmpty,
      );
    });

    test('ignores noise needles shorter than three characters', () {
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>['No', 'No Pork'],
          foodTags: const <String>['no pork'],
        ),
        <String>['No Pork'], // "No" alone is too short to be meaningful
      );
    });

    test('returns several conflicts at once, in the user list order', () {
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>['No Pork', 'High Calorie'],
          foodTags: const <String>['Pork', 'High calorie'],
        ),
        <String>['No Pork', 'High Calorie'],
      );
    });

    test('empty user restrictions or tags never conflict', () {
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>[],
          foodTags: const <String>['Pork'],
        ),
        isEmpty,
      );
      expect(
        FoodRecognitionLogic.dietaryConflicts(
          userRestrictions: const <String>['No Pork'],
          foodTags: const <String>[],
        ),
        isEmpty,
      );
    });
  });
}
