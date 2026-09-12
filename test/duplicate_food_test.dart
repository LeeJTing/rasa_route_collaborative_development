import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food(String name, {int id = 0}) => LocalFood(
  id: id,
  name: name,
  description: '',
  origin: '',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: '',
  mealType: '',
  foodType: 'Food',
);

void main() {
  group('LandmarkSubmissionLogic.isSameDishAndVariant', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

    test('the same dish and variant is a duplicate', () {
      // Case/punctuation never split a dish...
      expect(
        logic.isSameDishAndVariant(
          _food('Murtabak'),
          '',
          _food('  murtabak '),
          '',
        ),
        isTrue,
      );
      // ...and a renamed catalogue row still matches by id.
      expect(
        logic.isSameDishAndVariant(
          _food('Cendol', id: 375),
          'Cendol Jagung',
          _food('Nyonya Cendol', id: 375),
          'cendol   jagung',
        ),
        isTrue,
      );
    });

    test('a different variant, or a different dish, is not a duplicate', () {
      expect(
        logic.isSameDishAndVariant(
          _food('Cendol', id: 375),
          'Cendol Jagung',
          _food('Cendol', id: 375),
          'Cendol Special',
        ),
        isFalse,
      );
      // A plain dish and its recorded variant are different things to add.
      expect(
        logic.isSameDishAndVariant(
          _food('Cendol', id: 375),
          '',
          _food('Cendol', id: 375),
          'Cendol Jagung',
        ),
        isFalse,
      );
      expect(
        logic.isSameDishAndVariant(
          _food('Murtabak'),
          '',
          _food('Roti Canai'),
          '',
        ),
        isFalse,
      );
    });
  });

  group('AddLandmarkViewModel.addAdditionalFood duplicate guard', () {
    test('rejects a dish already on the form with the same variant', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.setRecognizedFood(_food('Murtabak'));

      vm.addAdditionalFood(_food('  murtabak '));

      expect(vm.additionalFoods, isEmpty);
      expect(vm.takeDuplicateFoodNotice(), isTrue);
      // The notice is consumed once.
      expect(vm.takeDuplicateFoodNotice(), isFalse);
      vm.dispose();
    });

    test('accepts the same dish with a DIFFERENT variant, then blocks '
        'the duplicate', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.setRecognizedFood(_food('Cendol', id: 375));

      // A different variant is a different thing to add.
      vm.addAdditionalFood(_food('Cendol', id: 375), variant: 'Cendol Jagung');
      expect(vm.additionalFoods.length, 1);
      expect(vm.takeDuplicateFoodNotice(), isFalse);

      // The SAME variant a second time is the duplicate case.
      vm.addAdditionalFood(_food('Cendol', id: 375), variant: 'Cendol Jagung');
      expect(vm.additionalFoods.length, 1);
      expect(vm.takeDuplicateFoodNotice(), isTrue);
      vm.dispose();
    });

    test(
      'a second additional food is also checked against the first',
      () async {
        final AddLandmarkViewModel vm = AddLandmarkViewModel();
        await vm.onInit();
        vm.setRecognizedFood(_food('Nasi Lemak'));

        vm.addAdditionalFood(_food('Teh Tarik'));
        expect(vm.additionalFoods.length, 1);

        vm.addAdditionalFood(_food('teh  tarik'));
        expect(vm.additionalFoods.length, 1);
        expect(vm.takeDuplicateFoodNotice(), isTrue);
        vm.dispose();
      },
    );
  });
}
