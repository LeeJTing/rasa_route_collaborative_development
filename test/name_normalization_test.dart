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

  group('detailValueKey', () {
    test('folds case and inner spacing, but never content', () {
      expect(
        detailValueKey('  Jalan  AMPANG '),
        detailValueKey('jalan ampang'),
      );
      expect(
        detailValueKey('https://TianYiKopitiam.my'),
        detailValueKey('https://tianyikopitiam.my'),
      );
      expect(
        detailValueKey('12, Jalan Alor'),
        isNot(detailValueKey('12, Jalan Alor 50450')),
      );
      // Punctuation is content: the same number written with different
      // separators stays a change, exactly as the merge rule has always
      // treated it.
      expect(
        detailValueKey('0123456789'),
        isNot(detailValueKey('012-345 6789')),
      );
    });

    test('null and blank values share the empty key', () {
      expect(detailValueKey(null), '');
      expect(detailValueKey('   '), '');
    });
  });

  group('chineseScriptStyleOf', () {
    test('tells the two styles apart', () {
      expect(chineseScriptStyleOf('海天樓'), 'traditional');
      expect(chineseScriptStyleOf('海天楼'), 'simplified');
    });

    test('reports a name that mixes both styles', () {
      expect(chineseScriptStyleOf('海天樓记'), 'mixed');
    });

    test('dual-role glyphs prove nothing about the style', () {
      // 皇后 is written identically in the two styles - 后 is not evidence.
      expect(chineseScriptStyleOf('皇后'), 'unknown');
      expect(chineseScriptStyleOf('面'), 'unknown');
    });

    test('shared-only glyphs and non-Chinese text are "unknown"', () {
      expect(chineseScriptStyleOf('海天'), 'unknown');
      expect(chineseScriptStyleOf('Village Park Restaurant'), 'unknown');
      expect(chineseScriptStyleOf(''), 'unknown');
    });
  });

  group('correctChineseScriptStyle', () {
    test('restores the complex form when the sign is Traditional', () {
      expect(correctChineseScriptStyle('天义', 'traditional'), '天義');
      expect(correctChineseScriptStyle('海天楼', 'traditional'), '海天樓');
      expect(correctChineseScriptStyle('天义记', 'traditional'), '天義記');
      // Already Traditional - nothing to correct.
      expect(correctChineseScriptStyle('天義', 'traditional'), '天義');
    });

    test('folds to the simple form when the sign is Simplified', () {
      expect(correctChineseScriptStyle('天義', 'simplified'), '天义');
      expect(correctChineseScriptStyle('海天樓', 'simplified'), '海天楼');
      expect(correctChineseScriptStyle('海天樓记', 'simplified'), '海天楼记');
      expect(correctChineseScriptStyle('天义', 'simplified'), '天义');
    });

    test('never invents glyphs it cannot prove', () {
      // 发 is the Simplified form of both 發 and 髮 - no single origin.
      expect(correctChineseScriptStyle('发', 'traditional'), '发');
      // 后 is a legitimate Traditional glyph (皇后) - never rewritten.
      expect(correctChineseScriptStyle('皇后', 'traditional'), '皇后');
      // 馆 was simplified from more than one Traditional form.
      expect(correctChineseScriptStyle('馆', 'traditional'), '馆');
      // Shared glyphs, other claims and non-Chinese text pass through.
      expect(correctChineseScriptStyle('海天', 'traditional'), '海天');
      expect(correctChineseScriptStyle('天义', 'n/a'), '天义');
      expect(correctChineseScriptStyle('天义', 'mixed'), '天义');
      expect(
        correctChineseScriptStyle('Village Park', 'traditional'),
        'Village Park',
      );
    });
  });
}
