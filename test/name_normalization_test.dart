import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/name_normalization.dart';

void main() {
  group('toSimplifiedChinese', () {
    test('converts known Traditional glyphs to Simplified', () {
      expect(toSimplifiedChinese('天義'), '天义');
      expect(toSimplifiedChinese('福建麵'), '福建面');
      expect(toSimplifiedChinese('雞飯'), '鸡饭');
      expect(toSimplifiedChinese('摩摩喳喳'), '摩摩喳喳'); // already simplified
    });

    test('converts characters far beyond the old curated list (full OpenCC '
        'table)', () {
      // 藝/術/醫/雙/樓/廣/場 were NOT in the small curated map - they now
      // resolve via the generated full table. 囍 has no simplified form and
      // correctly passes through unchanged.
      expect(toSimplifiedChinese('藝術醫院雙囍樓廣場'), '艺术医院双囍楼广场');
      expect(toSimplifiedChinese('時鐘'), '时钟');
      expect(toSimplifiedChinese('濟南雞飯'), '济南鸡饭');
      expect(toSimplifiedChinese('龍蝦麵'), '龙虾面');
    });

    test('leaves unknown characters and non-Chinese text untouched', () {
      expect(toSimplifiedChinese('abc 123'), 'abc 123');
      expect(toSimplifiedChinese(''), '');
      expect(toSimplifiedChinese('Nasi Lemak'), 'Nasi Lemak');
    });
  });

  group('placeNameKey', () {
    test(
      'folds script, trims and lowercases but keeps interior punctuation',
      () {
        expect(placeNameKey('  天義 TIAN YI  '), '天义 tian yi');
        expect(placeNameKey('天义 (Tian Yi)'), '天义 (tian yi)');
      },
    );

    test('a Traditional name and its Simplified sibling share a key', () {
      expect(placeNameKey('天義 (Tian Yi)'), placeNameKey('天义 (Tian Yi)'));
    });

    test('an empty/whitespace name stays empty', () {
      expect(placeNameKey(''), '');
      expect(placeNameKey('   '), '');
    });
  });
}
