import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food(String name) => LocalFood(
  id: 0,
  name: name,
  description: 'Description of $name',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: 'Frying',
  mealType: 'Breakfast',
  foodType: 'Food',
);

/// The Add-Landmark price rules (A16, reworked 2026-09-13): the band is
/// 0.01-9999.99 MYR, a leading zero can never be displayed (it is rewritten
/// while typing), and every valid price shows two decimals once the field is
/// left.
void main() {
  final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

  group('LandmarkSubmissionLogic.isValidPrice', () {
    test('accepts 0.01 through 9999.99 inclusive', () {
      expect(logic.isValidPrice(0.01), isTrue);
      expect(logic.isValidPrice(1), isTrue);
      expect(logic.isValidPrice(1000), isTrue);
      // The OLD cap is gone - a RM 1,001 dish is a valid price now.
      expect(logic.isValidPrice(1001), isTrue);
      expect(logic.isValidPrice(9999.99), isTrue);
    });

    test('rejects zero, negatives and anything above the cap', () {
      expect(logic.isValidPrice(0), isFalse);
      expect(logic.isValidPrice(-1), isFalse);
      expect(logic.isValidPrice(0.009), isFalse);
      expect(logic.isValidPrice(10000), isFalse);
    });
  });

  group('normalisePriceEntryText (while typing)', () {
    test('rewrites a leading zero to the value with exactly 2 decimals', () {
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('01'), '1.00');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('02'), '2.00');
      expect(
        LandmarkSubmissionLogic.normalisePriceEntryText('0010.00'),
        '10.00',
      );
      expect(
        LandmarkSubmissionLogic.normalisePriceEntryText('0010.25'),
        '10.25',
      );
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('01.5'), '1.50');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('00.50'), '0.50');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('01.'), '1.00');
    });

    test('collapses an all-zero entry to a single 0', () {
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('00'), '0');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('000'), '0');
    });

    test('leaves untouched anything that is not a leading-zero value', () {
      // The lone 0 of a "0.xx" entry in progress must survive.
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('0'), '0');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('0.'), '0.');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('0.50'), '0.50');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('1'), '1');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('10'), '10');
      expect(LandmarkSubmissionLogic.normalisePriceEntryText('10.25'), '10.25');
      expect(
        LandmarkSubmissionLogic.normalisePriceEntryText('9999.99'),
        '9999.99',
      );
      expect(LandmarkSubmissionLogic.normalisePriceEntryText(''), '');
    });
  });

  group('formatPriceText (on leaving the field)', () {
    test('pads every valid price to exactly 2 decimals', () {
      expect(LandmarkSubmissionLogic.formatPriceText('1'), '1.00');
      expect(LandmarkSubmissionLogic.formatPriceText('1.5'), '1.50');
      expect(LandmarkSubmissionLogic.formatPriceText('0.5'), '0.50');
      expect(LandmarkSubmissionLogic.formatPriceText('10'), '10.00');
      expect(LandmarkSubmissionLogic.formatPriceText('12.'), '12.00');
      expect(LandmarkSubmissionLogic.formatPriceText('12.50'), '12.50');
    });

    test('leaves empty, junk and zero unchanged', () {
      expect(LandmarkSubmissionLogic.formatPriceText(''), '');
      expect(LandmarkSubmissionLogic.formatPriceText('0'), '0');
      expect(LandmarkSubmissionLogic.formatPriceText('0.00'), '0.00');
    });
  });

  group('AddLandmarkViewModel price messages', () {
    test('quotes the new band and accepts 1001 MYR', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.setRecognizedFood(_food('Cendol'));

      vm.setPrimaryFoodPrice(1001);
      expect(vm.primaryFoodPrice, 1001);
      expect(vm.submitError, isNull);

      vm.setPrimaryFoodPrice(10000);
      // The band is quoted the way the report flow quotes it - RM, two
      // decimals, thousands-separated - not "0.01 and 9999.99 MYR".
      expect(vm.submitError, 'Price must be between RM0.01 and RM9,999.99.');
      vm.dispose();
    });
  });
}
