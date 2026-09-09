import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_name_matcher.dart';

LocalFood _food(
  int id,
  String name, {
  List<String> synonyms = const <String>[],
}) => LocalFood(
  id: id,
  name: name,
  description: 'Description of $name',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: '',
  mealType: '',
  foodType: 'Food',
  synonyms: synonyms,
);

void main() {
  group('FoodNameMatcher.normalize', () {
    test('lowercases, strips punctuation and collapses whitespace', () {
      expect(
        FoodNameMatcher.normalize('  Nasi Lemak (Ayam)  ! '),
        'nasi lemak ayam',
      );
    });

    test('leaves plain lowercase names unchanged', () {
      expect(FoodNameMatcher.normalize('nasi lemak'), 'nasi lemak');
    });

    test('folds Traditional Chinese into Simplified', () {
      expect(FoodNameMatcher.normalize('天義 TIAN YI'), '天义 tian yi');
      expect(FoodNameMatcher.normalize('福建麵'), '福建面');
    });
  });

  group('FoodNameMatcher.bestMatch', () {
    test('exact name match wins', () {
      final nasiLemak = _food(1, 'Nasi Lemak');
      final result = FoodNameMatcher.bestMatch('nasi lemak', <LocalFood>[
        nasiLemak,
      ]);
      expect(result, same(nasiLemak));
    });

    test('exact synonym match wins', () {
      final nasiLemak = _food(
        1,
        'Nasi Lemak',
        synonyms: <String>['nasi lemak bungkus'],
      );
      final result = FoodNameMatcher.bestMatch(
        'Nasi Lemak Bungkus',
        <LocalFood>[nasiLemak],
      );
      expect(result, same(nasiLemak));
    });

    test(
      'a Traditional-script dish name matches a Simplified catalogue row',
      () {
        final hokkienMee = _food(1, 'Hokkien Mee', synonyms: <String>['福建面']);
        final result = FoodNameMatcher.bestMatch('福建麵', <LocalFood>[
          hokkienMee,
        ]);
        expect(result, same(hokkienMee));
      },
    );

    test('exact beats fuzzy - a specific Gemini name uses the exact row', () {
      final nasiLemak = _food(1, 'Nasi Lemak');
      final nasiLemakAyam = _food(2, 'Nasi Lemak Ayam');
      final result = FoodNameMatcher.bestMatch('nasi lemak ayam', <LocalFood>[
        nasiLemak,
        nasiLemakAyam,
      ]);
      expect(result, same(nasiLemakAyam));
    });

    test('a more specific Gemini name resolves to the curated base dish', () {
      final nasiLemak = _food(1, 'Nasi Lemak');
      final result = FoodNameMatcher.bestMatch('nasi lemak ayam', <LocalFood>[
        nasiLemak,
      ]);
      expect(result, same(nasiLemak));
    });

    test('longest prefix wins when several curated names prefix the dish', () {
      final nasi = _food(1, 'Nasi');
      final nasiLemak = _food(2, 'Nasi Lemak');
      final result = FoodNameMatcher.bestMatch('nasi lemak ayam', <LocalFood>[
        nasi,
        nasiLemak,
      ]);
      expect(result, same(nasiLemak));
    });

    test('prefix is a whole word - a partial word never matches', () {
      final nasi = _food(1, 'Nasi');
      // "nasik" is a different word; "nasi" must not match as a prefix of it.
      expect(
        FoodNameMatcher.bestMatch('nasik lemak', <LocalFood>[nasi]),
        isNull,
      );
      // But the full word "nasi" at the start of "nasi lemak" does match.
      expect(
        FoodNameMatcher.bestMatch('nasi lemak', <LocalFood>[nasi]),
        same(nasi),
      );
    });

    test('a curated name contained mid-phrase still matches', () {
      final meeGoreng = _food(1, 'Mee Goreng');
      final result = FoodNameMatcher.bestMatch(
        'special mee goreng',
        <LocalFood>[meeGoreng],
      );
      expect(result, same(meeGoreng));
    });

    test('short generic words are ignored by the fuzzy tiers', () {
      final mee = _food(1, 'Mee');
      // "mee" (3 chars) is below the fuzzy minimum, so a compound dish name
      // never collapses onto the generic word alone.
      expect(FoodNameMatcher.bestMatch('mee goreng', <LocalFood>[mee]), isNull);
    });

    test('matching is one-directional - a short name never expands', () {
      final nasiLemakAyam = _food(1, 'Nasi Lemak Ayam');
      // "nasi lemak" must NOT be claimed as the "nasi lemak ayam" variant.
      expect(
        FoodNameMatcher.bestMatch('nasi lemak', <LocalFood>[nasiLemakAyam]),
        isNull,
      );
    });

    test('no match returns null', () {
      final nasiLemak = _food(1, 'Nasi Lemak');
      expect(
        FoodNameMatcher.bestMatch('pepperoni pizza', <LocalFood>[nasiLemak]),
        isNull,
      );
      expect(FoodNameMatcher.bestMatch('nasi lemak', <LocalFood>[]), isNull);
      expect(FoodNameMatcher.bestMatch('   ', <LocalFood>[nasiLemak]), isNull);
    });
  });
}
