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

  group('FoodNameMatcher.variantDistinction', () {
    const List<String> aisKacangSynonyms = <String>[
      'ABC',
      'air batu campur',
      'ice kacang',
      'mixed shaved ice',
      '红豆冰',
    ];

    test(
      'a spelling that only repeats the dish or its synonyms adds nothing',
      () {
        // The reported duplication: "Ais Kacang (ABC)" - 'ABC' IS a curated
        // synonym of "Ais Kacang" (the live row lists it), so there is no
        // variant here at all.
        expect(
          FoodNameMatcher.variantDistinction(
            'Ais Kacang',
            'Ais Kacang (ABC)',
            aisKacangSynonyms,
          ),
          '',
        );
        expect(
          FoodNameMatcher.variantDistinction(
            'Ais Kacang',
            'Ais Kacang',
            aisKacangSynonyms,
          ),
          '',
        );
        expect(
          FoodNameMatcher.variantDistinction(
            'Ais Kacang',
            'Ais Kacang (ice kacang)',
            aisKacangSynonyms,
          ),
          '',
        );
      },
    );

    test('a real variant keeps its distinguishing words', () {
      expect(
        FoodNameMatcher.variantDistinction('Cendol', 'Cendol Jagung', <String>[
          'Chendol',
          '煎蕊',
        ]),
        'jagung',
      );
      expect(
        FoodNameMatcher.variantDistinction(
          'Ais Kacang',
          'Ais Kacang Special',
          aisKacangSynonyms,
        ),
        'special',
      );
      // Case and punctuation never split a word.
      expect(
        FoodNameMatcher.variantDistinction(
          'Cendol',
          'CENDOL - Jagung!',
          const <String>[],
        ),
        'jagung',
      );
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

    test('a "Cendol Jagung" variant resolves to the curated Cendol row '
        '(so no new food row is created)', () {
      // The live catalogue shape: 'Cendol' (375), 'Nyonya Cendol' (58) and
      // 'Durian Cendol' (86) coexist. Only the plain 'Cendol' row prefixes
      // the variant name, so "cendol jagung" links to it - and
      // `FoodRecognitionLogic.registerNewDishes` skips the insert for any
      // dish `bestMatch` already resolves.
      final cendol = _food(
        375,
        'Cendol',
        synonyms: <String>['chendol', 'cendol pulut', 'cendol gula Melaka'],
      );
      final nyonya = _food(58, 'Nyonya Cendol', synonyms: <String>['chendol']);
      final durian = _food(
        86,
        'Durian Cendol',
        synonyms: <String>['cendol durian'],
      );
      final catalogue = <LocalFood>[cendol, nyonya, durian];

      expect(
        FoodNameMatcher.bestMatch('Cendol Jagung', catalogue),
        same(cendol),
      );
      // An exact variant synonym still beats the plain prefix.
      expect(
        FoodNameMatcher.bestMatch('cendol durian', catalogue),
        same(durian),
      );
    });

    test('a "nasi kukus ..." variant resolves to the merged curated row', () {
      final nasiKukus = _food(
        19,
        'Nasi Kukus Ayam Goreng Berempah',
        synonyms: <String>['nasi kukus', 'nasi kukus ayam berempah'],
      );
      final catalogue = <LocalFood>[nasiKukus];

      expect(
        FoodNameMatcher.bestMatch('nasi kukus', catalogue),
        same(nasiKukus),
      );
      expect(
        FoodNameMatcher.bestMatch('nasi kukus ayam berempah', catalogue),
        same(nasiKukus),
      );
      expect(
        FoodNameMatcher.bestMatch('nasi kukus special', catalogue),
        same(nasiKukus),
      );
    });

    test('a spelling shared by several rows resolves to the basest row', () {
      // 'chendol' and 煎蕊 sit on both the plain and the Nyonya row - the
      // plain base row (fewest words in its name) must win, so a generic
      // spelling never lands on a specific dessert.
      final nyonya = _food(
        58,
        'Nyonya Cendol',
        synonyms: <String>['chendol', '煎蕊'],
      );
      final cendol = _food(375, 'Cendol', synonyms: <String>['chendol', '煎蕊']);
      final catalogue = <LocalFood>[nyonya, cendol];

      expect(FoodNameMatcher.bestMatch('chendol', catalogue), same(cendol));
      expect(FoodNameMatcher.bestMatch('煎蕊', catalogue), same(cendol));
    });

    test('a word-order spelling is the SAME dish, not a variant', () {
      final cendol = _food(
        375,
        'Cendol',
        synonyms: <String>['chendol', 'cendol pulut'],
      );
      final nyonya = _food(
        58,
        'Nyonya Cendol',
        synonyms: <String>['Melaka cendol'],
      );
      final catalogue = <LocalFood>[cendol, nyonya];

      // "cendol nyonya" is "Nyonya Cendol" written back-to-front; without
      // this tier the plain 'Cendol' prefix would wrongly claim it.
      expect(
        FoodNameMatcher.bestMatch('cendol nyonya', catalogue),
        same(nyonya),
      );
      // Same for a reversed synonym ("cendol melaka" / "Melaka cendol").
      expect(
        FoodNameMatcher.bestMatch('cendol melaka', catalogue),
        same(nyonya),
      );
      // The tier reports WHY the match happened: same dish, any order...
      expect(
        FoodNameMatcher.bestMatchDetailed('cendol nyonya', catalogue)?.tier,
        FoodMatchTier.sameWords,
      );
      // ...while a genuinely unlisted extension reports the prefix tier.
      expect(
        FoodNameMatcher.bestMatchDetailed('cendol jagung', catalogue)?.tier,
        FoodMatchTier.prefix,
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
