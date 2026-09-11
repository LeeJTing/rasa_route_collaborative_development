import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

void main() {
  group(
    'LandmarkSubmissionLogic.sanitiseSignboardName (lot/phone exclusion)',
    () {
      test(
        'drops lot number, address, postcode and phone from a comma list',
        () {
          const String raw =
              'Restoran ABC, Lot 12, Jalan Ampang, 50450 Kuala Lumpur, '
              'Tel: 012-345 6789';
          expect(
            LandmarkSubmissionLogic.sanitiseSignboardName(raw),
            'Restoran ABC',
          );
        },
      );

      test('drops noise from a multi-line signboard', () {
        const String raw =
            'Nasi Kandar Pelita\nLot No. 12\nJalan Tun Razak\nTel: 03-1234 5678';
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName(raw),
          'Nasi Kandar Pelita',
        );
      });

      test('strips a phone number glued to the name without a comma', () {
        const String raw = 'Restoran ABC Tel: 012-345 6789';
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName(raw),
          'Restoran ABC',
        );
      });

      test('leaves a clean name untouched', () {
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName(
            'Village Park Restaurant',
          ),
          'Village Park Restaurant',
        );
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName('海天楼 Hai Tian Lou'),
          '海天楼 Hai Tian Lou',
        );
      });

      test('keeps a name that legitimately starts with "No."', () {
        // "No. 1 Noodle Bar" is a name - more words than a bare unit number,
        // so it must not be treated as an address segment.
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName('No. 1 Noodle Bar'),
          'No. 1 Noodle Bar',
        );
      });

      test('returns empty when the raw text was only noise', () {
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName('012-345 6789'),
          '',
        );
        expect(
          LandmarkSubmissionLogic.sanitiseSignboardName('Lot 12, Jalan Ampang'),
          '',
        );
      });
    },
  );

  group('LandmarkSubmissionLogic.displaySignboardName (signboard text)', () {
    test('returns the exact signboard text for a non-Latin sign', () {
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: '海天楼',
          languageScript: 'chinese',
        ),
        '海天楼',
      );
    });

    test('returns just the romanised name for a Latin sign', () {
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Village Park Restaurant',
          originalScript: 'Village Park Restaurant',
          languageScript: 'latin',
        ),
        'Village Park Restaurant',
      );
    });

    test('returns romanised when original is missing or identical', () {
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: null,
          languageScript: 'chinese',
        ),
        'Hai Tian Lou',
      );
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: 'Hai Tian Lou',
          languageScript: 'chinese',
        ),
        'Hai Tian Lou',
      );
    });

    test('ignores noise inside the original-script field', () {
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Nasi Kandar Pelita',
          originalScript: 'ناسي كاندار, Tel: 012-345 6789',
          languageScript: 'jawi',
        ),
        'ناسي كاندار',
      );
    });
  });

  group('LandmarkSubmissionLogic signboard script-variant check', () {
    test('a "turned" transcription is restored to the reported style', () {
      // The sign is reported Simplified, but the model wrote the Traditional
      // glyphs - they are folded back to the style it reported.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: '海天樓',
          languageScript: 'chinese',
          scriptVariant: 'simplified',
        ),
        '海天楼',
      );
      // ...and the other way round: sign Traditional, transcription
      // Simplified - the Traditional glyphs are restored.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: '海天楼',
          languageScript: 'chinese',
          scriptVariant: 'traditional',
        ),
        '海天樓',
      );
      // A Traditional glyph that slipped into a Simplified transcription is
      // folded too.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou Ji',
          originalScript: '海天樓记',
          languageScript: 'chinese',
          scriptVariant: 'simplified',
        ),
        '海天楼记',
      );
    });

    test('a contradiction the app cannot fully correct loses to the '
        'romanised name', () {
      // 发 (the Simplified form of both 發 and 髮) cannot be restored to one
      // Traditional form, so the transcription stays mixed and the
      // romanised name is the safer value.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Tian Yi Fa',
          originalScript: '天义发',
          languageScript: 'chinese',
          scriptVariant: 'traditional',
        ),
        'Tian Yi Fa',
      );
    });

    test('a painted Latin line inside the name is preserved', () {
      // The signboard paints 天義 with "Tian Yi" beneath it - the model
      // copies both, and the script correction touches only the Chinese
      // glyphs.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Tian Yi',
          originalScript: '天義 Tian Yi',
          languageScript: 'chinese',
          scriptVariant: 'traditional',
        ),
        '天義 Tian Yi',
      );
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Tian Yi',
          originalScript: '天義 Tian Yi',
          languageScript: 'chinese',
          scriptVariant: 'simplified',
        ),
        '天义 Tian Yi',
      );
    });

    test('an exact transcription survives the check', () {
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: '海天楼',
          languageScript: 'chinese',
          scriptVariant: 'simplified',
        ),
        '海天楼',
      );
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: '海天樓',
          languageScript: 'chinese',
          scriptVariant: 'traditional',
        ),
        '海天樓',
      );
      // "mixed" is the honest answer for a sign that mixes styles.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou Ji',
          originalScript: '海天樓记',
          languageScript: 'chinese',
          scriptVariant: 'mixed',
        ),
        '海天樓记',
      );
    });

    test('names without style-specific glyphs never conflict', () {
      // 海天 look the same in both styles - nothing to contradict.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian',
          originalScript: '海天',
          languageScript: 'chinese',
          scriptVariant: 'simplified',
        ),
        '海天',
      );
      // Dual-role glyphs (后 in 皇后) are not evidence either.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Huang Hou',
          originalScript: '皇后',
          languageScript: 'chinese',
          scriptVariant: 'traditional',
        ),
        '皇后',
      );
      // A response without the field defaults to "n/a" - no check.
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: 'Hai Tian Lou',
          originalScript: '海天樓',
          languageScript: 'chinese',
        ),
        '海天樓',
      );
    });

    test('restores the reported style even with no romanised fallback', () {
      expect(
        LandmarkSubmissionLogic.displaySignboardName(
          romanised: '',
          originalScript: '海天樓',
          languageScript: 'chinese',
          scriptVariant: 'simplified',
        ),
        '海天楼',
      );
    });

    test('isScriptVariantContradiction only fires on a definite clash', () {
      expect(
        LandmarkSubmissionLogic.isScriptVariantContradiction(
          text: '海天樓',
          scriptVariant: 'simplified',
        ),
        isTrue,
      );
      expect(
        LandmarkSubmissionLogic.isScriptVariantContradiction(
          text: '海天樓',
          scriptVariant: 'traditional',
        ),
        isFalse,
      );
      expect(
        LandmarkSubmissionLogic.isScriptVariantContradiction(
          text: '海天樓',
          scriptVariant: 'n/a',
        ),
        isFalse,
      );
      expect(
        LandmarkSubmissionLogic.isScriptVariantContradiction(
          text: '海天',
          scriptVariant: 'simplified',
        ),
        isFalse,
      );
    });
  });
}
