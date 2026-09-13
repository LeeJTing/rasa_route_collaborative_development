import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/signboard_script_check_response.dart';

/// The wire shape of the separately-framed "which Chinese style is PAINTED on
/// this sign?" answer (see `SignboardScriptCheckResponse`) - what
/// `LandmarkSubmissionLogic.applyPaintedScript` acts on.
void main() {
  group('SignboardScriptCheckResponse (painted-script check)', () {
    test('parses the two styles that name a restoration', () {
      final SignboardScriptCheckResponse traditional =
          SignboardScriptCheckResponse.fromJson(<String, dynamic>{
            'paintedStyle': 'traditional',
            'exampleCharacters': '天義樓',
            'reason': '樓 carries the full complex strokes',
          });

      expect(traditional.paintedStyle, 'traditional');
      expect(traditional.exampleCharacters, '天義樓');
      expect(traditional.namesAStyle, isTrue);
      expect(traditional.toJson()['paintedStyle'], 'traditional');

      expect(
        SignboardScriptCheckResponse.fromJson(<String, dynamic>{
          'paintedStyle': ' Simplified ',
        }).paintedStyle,
        'simplified',
      );
    });

    test('an unusable or absent answer normalises to "unknown"', () {
      // The model answered something the app cannot act on, or the field was
      // missing entirely: callers keep the first reading, exactly as they do
      // for a check that could not run.
      for (final Object? raw in <Object?>[null, '', '  ', 'n/a', 'mixed', 7]) {
        final SignboardScriptCheckResponse response =
            SignboardScriptCheckResponse.fromJson(<String, dynamic>{
              'paintedStyle': raw,
            });
        expect(response.paintedStyle, 'unknown');
        expect(response.namesAStyle, isFalse);
      }
    });

    test('"none" means the sign has no Chinese at all', () {
      final SignboardScriptCheckResponse response =
          SignboardScriptCheckResponse.fromJson(<String, dynamic>{
            'paintedStyle': 'none',
          });

      expect(response.paintedStyle, 'none');
      expect(response.namesAStyle, isFalse);
    });
  });
}
