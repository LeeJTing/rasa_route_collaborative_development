import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/signboard_analysis_response.dart';

void main() {
  group('SignboardAnalysisResponse (multilingual signboard, UC500)', () {
    test('defaults languageScript to latin when omitted', () {
      const SignboardAnalysisResponse latin = SignboardAnalysisResponse(
        signboardStatus: 'detected',
        textDetected: 'Nasi Kandar Pelita',
        signboardImageStatus: 'complete',
      );
      expect(latin.languageScript, 'latin');
      expect(latin.nameOriginalScript, isNull);
      expect(latin.scriptVariant, 'n/a');
    });

    test('carries the original-script name and script for non-Latin signs', () {
      const SignboardAnalysisResponse chinese = SignboardAnalysisResponse(
        signboardStatus: 'detected',
        textDetected: 'Hai Tian Lou',
        nameOriginalScript: '海天楼',
        scriptVariant: 'simplified',
        languageScript: 'chinese',
        signboardImageStatus: 'complete',
        confidence: 0.95,
      );
      expect(chinese.textDetected, 'Hai Tian Lou');
      expect(chinese.nameOriginalScript, '海天楼');
      expect(chinese.scriptVariant, 'simplified');
      expect(chinese.languageScript, 'chinese');
      expect(chinese.confidence, 0.95);
    });

    test('toJson includes the new multilingual fields', () {
      const SignboardAnalysisResponse jawi = SignboardAnalysisResponse(
        signboardStatus: 'detected',
        textDetected: 'Warung Makan Kita',
        nameOriginalScript: 'واروڠ مكن كيت',
        languageScript: 'jawi',
        signboardImageStatus: 'complete',
      );
      expect(jawi.toJson()['nameOriginalScript'], 'واروڠ مكن كيت');
      expect(jawi.toJson()['scriptVariant'], 'n/a');
      expect(jawi.toJson()['languageScript'], 'jawi');
      expect(jawi.toJson()['textDetected'], 'Warung Makan Kita');
    });

    test('copyWith updates the new fields without disturbing others', () {
      const SignboardAnalysisResponse original = SignboardAnalysisResponse(
        signboardStatus: 'detected',
        textDetected: 'Kopitiam',
        signboardImageStatus: 'complete',
      );
      final SignboardAnalysisResponse updated = original.copyWith(
        textDetected: 'Ah Kow Kopitiam',
        nameOriginalScript: '阿狗咖啡店',
        scriptVariant: 'traditional',
        languageScript: 'mixed',
      );
      expect(updated.textDetected, 'Ah Kow Kopitiam');
      expect(updated.nameOriginalScript, '阿狗咖啡店');
      expect(updated.scriptVariant, 'traditional');
      expect(updated.languageScript, 'mixed');
      // Untouched fields keep their original values.
      expect(updated.signboardStatus, 'detected');
      expect(updated.signboardImageStatus, 'complete');
    });
  });
}
