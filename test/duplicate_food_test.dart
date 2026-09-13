import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food(
  String name, {
  int id = 0,
  List<String> synonyms = const <String>[],
}) => LocalFood(
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
  synonyms: synonyms,
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

    test(
      "a 'variant' that only repeats the dish's own synonym is the SAME dish "
      '( Ais Kacang (ABC) vs plain Ais Kacang )',
      () {
        const List<String> synonyms = <String>[
          'ABC',
          'air batu campur',
          'ice kacang',
        ];
        final LocalFood aisKacang = _food(
          'Ais Kacang',
          id: 250,
          synonyms: synonyms,
        );

        // The reported duplication: 'ABC' is one of the row's OWN synonyms,
        // so the parenthesised spelling carries no variant at all.
        expect(
          logic.isSameDishAndVariant(
            aisKacang,
            'Ais Kacang (ABC)',
            aisKacang,
            '',
          ),
          isTrue,
        );
        expect(
          logic.isSameDishAndVariant(
            aisKacang,
            'Ais Kacang (ABC)',
            aisKacang,
            'Ais Kacang (ice kacang)',
          ),
          isTrue,
        );
        // A word beyond the dish and its synonyms IS a real variant...
        expect(
          logic.isSameDishAndVariant(
            aisKacang,
            'Ais Kacang Special',
            aisKacang,
            '',
          ),
          isFalse,
        );
        // ...and a real variant still keeps the plain dish separate.
        final LocalFood cendol = _food(
          'Cendol',
          id: 375,
          synonyms: <String>['Chendol', '煎蕊'],
        );
        expect(
          logic.isSameDishAndVariant(cendol, 'Cendol Jagung', cendol, ''),
          isFalse,
        );
      },
    );
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

    test("rejects the plain dish when the form's entry only adds the dish's "
        'own synonym (the reported Ais Kacang duplication)', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      final LocalFood aisKacang = _food(
        'Ais Kacang',
        id: 250,
        synonyms: <String>['ABC', 'air batu campur', 'ice kacang'],
      );
      vm.setRecognizedFood(aisKacang, variant: 'Ais Kacang (ABC)');

      // The SAME dish spelled with its own alias is not a second entry.
      vm.addAdditionalFood(aisKacang);

      expect(vm.additionalFoods, isEmpty);
      expect(vm.takeDuplicateFoodNotice(), isTrue);
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

  group('real-catalogue duplicates (synonyms copied from the live rows)', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

    test("a spelling built from the dish's own synonyms is the same dish", () {
      final LocalFood aisKacang = _food(
        'Ais Kacang',
        id: 1,
        synonyms: <String>[
          'ABC',
          'air batu campur',
          'ice kacang',
          'mixed shaved ice',
          '红豆冰',
        ],
      );
      expect(
        logic.isSameDishAndVariant(
          aisKacang,
          'Ais Kacang (ABC)',
          aisKacang,
          '',
        ),
        isTrue,
      );

      final LocalFood cendol = _food(
        'Cendol',
        id: 2,
        synonyms: <String>[
          'Traditional Malaysian Cendol',
          'chendol',
          'cendol pulut',
          'cendol gula Melaka',
          'pandan jelly dessert',
        ],
      );
      expect(
        logic.isSameDishAndVariant(
          cendol,
          'Traditional Malaysian Cendol',
          cendol,
          '',
        ),
        isTrue,
      );

      final LocalFood ramly = _food(
        'Ramly Burger',
        id: 3,
        synonyms: <String>[
          'burger Ramly',
          'Malaysian street burger',
          'burger special',
          'burger tepi jalan',
        ],
      );
      expect(logic.isSameDishAndVariant(ramly, 'Special', ramly, ''), isTrue);
      expect(
        logic.isSameDishAndVariant(ramly, 'Burger Special', ramly, ''),
        isTrue,
      );

      final LocalFood bubur = _food(
        'Bubur Cha Cha',
        id: 4,
        synonyms: <String>[
          'Bubur Chacha',
          'Bubur Cha-Cha',
          'Bobochacha',
          'Bubocaca',
          'Bubur Ca Ca',
        ],
      );
      expect(
        logic.isSameDishAndVariant(bubur, 'Bubur Chacha', bubur, ''),
        isTrue,
      );
    });

    test('a genuinely different variant still counts as a separate item', () {
      final LocalFood cendol = _food(
        'Cendol',
        id: 2,
        synonyms: <String>[
          'Traditional Malaysian Cendol',
          'chendol',
          'cendol pulut',
          'cendol gula Melaka',
        ],
      );
      expect(
        logic.isSameDishAndVariant(cendol, 'Cendol Jagung', cendol, ''),
        isFalse,
      );

      final LocalFood nasiKukus = _food(
        'Nasi Kukus Ayam Goreng Berempah',
        id: 5,
        synonyms: <String>['nasi kukus', 'nasi kukus ayam berempah'],
      );
      // A word beyond the dish and its synonyms stays a real variant.
      expect(
        logic.isSameDishAndVariant(
          nasiKukus,
          'Nasi Kukus Ayam Goreng Berempah Special',
          nasiKukus,
          '',
        ),
        isFalse,
      );
    });
  });

  group('the form hands its dishes to the additional-food capture', () {
    test('formFoodIdentities lists the primary + additional dishes', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.setRecognizedFood(_food('Murtabak'), variant: 'Murtabak Special');
      vm.addAdditionalFood(_food('Teh Tarik'));

      final identities = vm.formFoodIdentities;
      expect(identities, hasLength(2));
      expect(identities[0].food.name, 'Murtabak');
      expect(identities[0].variant, 'Murtabak Special');
      expect(identities[1].food.name, 'Teh Tarik');
      expect(identities[1].variant, isEmpty);

      // One shared notice for both screens (camera block + form snackbar).
      expect(vm.duplicateFoodNotice, 'This dish is already on the form.');
      vm.dispose();
    });
  });
}
