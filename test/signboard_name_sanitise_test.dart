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

  group(
    'LandmarkSubmissionLogic.displaySignboardName (original + translated)',
    () {
      test('shows original then translated in parens for a non-Latin sign', () {
        expect(
          LandmarkSubmissionLogic.displaySignboardName(
            romanised: 'Hai Tian Lou',
            originalScript: '海天楼',
            languageScript: 'chinese',
          ),
          '海天楼 (Hai Tian Lou)',
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
          'ناسي كاندار (Nasi Kandar Pelita)',
        );
      });
    },
  );
}
