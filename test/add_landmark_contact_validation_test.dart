import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

void main() {
  final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

  group('Malaysian phone validation (format-level)', () {
    test('accepts common +60 / 0 prefixes with formatting', () {
      expect(logic.isValidMalaysianPhone('+60 12-345 6789'), isTrue);
      expect(logic.isValidMalaysianPhone('012-345 6789'), isTrue);
      expect(logic.isValidMalaysianPhone('0123456789'), isTrue);
      expect(logic.isValidMalaysianPhone('+60123456789'), isTrue);
      expect(logic.isValidMalaysianPhone('011-1234 5678'), isTrue);
      expect(logic.isValidMalaysianPhone('00601123456789'), isTrue);
      // Landlines.
      expect(logic.isValidMalaysianPhone('03-2148 0000'), isTrue);
      expect(logic.isValidMalaysianPhone('082-234 567'), isTrue);
      expect(logic.isValidMalaysianPhone('09-123 4567'), isTrue);
    });

    test('rejects non-Malaysian or malformed numbers', () {
      expect(logic.isValidMalaysianPhone('12345'), isFalse);
      expect(
        logic.isValidMalaysianPhone('+65 9123 4567'),
        isFalse,
      ); // Singapore
      expect(logic.isValidMalaysianPhone('0123456'), isFalse); // too short
      expect(logic.isValidMalaysianPhone('012345678901234567890'), isFalse);
      expect(logic.isValidMalaysianPhone(''), isFalse);
      expect(logic.isValidMalaysianPhone('not a phone'), isFalse);
      // '02' is not a Malaysian area code (Jakarta prefix) - strict reject.
      expect(logic.isValidMalaysianPhone('02-123 4567'), isFalse);
      expect(logic.isValidMalaysianPhone('0212345678'), isFalse);
    });
  });

  group('website format validation', () {
    test('accepts plain http(s) URLs with a dotted host', () {
      expect(logic.isValidWebsiteFormat('https://example.com'), isTrue);
      expect(logic.isValidWebsiteFormat('http://foodstall.my'), isTrue);
      expect(
        logic.isValidWebsiteFormat('https://example.com/menu?q=1'),
        isTrue,
      );
    });

    test('rejects missing scheme, credentials, spaces, bad hosts', () {
      expect(logic.isValidWebsiteFormat('example.com'), isFalse);
      expect(logic.isValidWebsiteFormat('ftp://example.com'), isFalse);
      expect(logic.isValidWebsiteFormat('https://'), isFalse);
      expect(
        logic.isValidWebsiteFormat('https://user:pass@example.com'),
        isFalse,
      );
      expect(logic.isValidWebsiteFormat('https://exa mple.com'), isFalse);
      expect(logic.isValidWebsiteFormat(''), isFalse);
      expect(
        logic.isValidWebsiteFormat(
          'https://example.com/${'x' * LandmarkSubmissionLogic.maxWebsiteLength}',
        ),
        isFalse,
      );
      // Strict: no localhost, no IP literals, real TLD, valid labels.
      expect(logic.isValidWebsiteFormat('http://localhost'), isFalse);
      expect(logic.isValidWebsiteFormat('http://192.168.1.1'), isFalse);
      expect(logic.isValidWebsiteFormat('http://10.0.0.5'), isFalse);
      expect(
        logic.isValidWebsiteFormat('https://a.b'),
        isFalse,
      ); // TLD too short
      expect(logic.isValidWebsiteFormat('https://foo_bar.com'), isFalse);
      expect(logic.isValidWebsiteFormat('https://-bad.com'), isFalse);
    });
  });

  group('address free-text validation', () {
    test('accepts common address characters incl. Chinese', () {
      expect(logic.isValidAddressText('12, Jalan Bukit Bintang, KL'), isTrue);
      expect(logic.isValidAddressText('No.12 Jalan ABC #3-4'), isTrue);
      expect(logic.isValidAddressText('Lot 123 & 124, Jalan Baru'), isTrue);
      expect(logic.isValidAddressText('吉隆坡 武吉免登路12号'), isTrue);
    });

    test('rejects control characters, unsupported symbols, digit-only', () {
      expect(logic.isValidAddressText('Jalan ABC\nSecond line'), isFalse);
      expect(logic.isValidAddressText('Jalan <> ABC'), isFalse);
      expect(logic.isValidAddressText('Jalan\u0000ABC'), isFalse);
      // No letters at all is not an address.
      expect(logic.isValidAddressText('12345'), isFalse);
      expect(logic.isValidAddressText('12, 34, #56-78'), isFalse);
    });

    test('blanket control-character guard', () {
      expect(logic.containsControlCharacters('abc'), isFalse);
      expect(logic.containsControlCharacters('abc\ndef'), isTrue);
      expect(logic.containsControlCharacters('abc\u0007def'), isTrue);
    });
  });

  group('restaurant name validation', () {
    test('accepts letters/digits with common name punctuation', () {
      expect(logic.isValidRestaurantNameText('Nasi Lemak Corner'), isTrue);
      expect(logic.isValidRestaurantNameText('R&R Cafe (1988)'), isTrue);
      expect(logic.isValidRestaurantNameText('美心茶室'), isTrue);
      expect(logic.isValidRestaurantNameText('Kedai Kopi, Jalan 1'), isTrue);
      expect(logic.isValidRestaurantNameText('Restaurant: A/B'), isTrue);
      // Numeric-only still counts (contains digits) but is unusual.
      expect(logic.isValidRestaurantNameText('888'), isTrue);
    });

    test('rejects symbols-only, control chars and unsupported glyphs', () {
      expect(logic.isValidRestaurantNameText('@@##%%'), isFalse);
      expect(logic.isValidRestaurantNameText('   '), isFalse);
      expect(logic.isValidRestaurantNameText('Kedai\u0000'), isFalse);
      expect(logic.isValidRestaurantNameText('Kedai<>X'), isFalse);
      expect(logic.isValidRestaurantNameText('Kedai 😀'), isFalse);
    });
  });

  group('field caps', () {
    test('name: stop 40, warn 31, submit <=30; website: stop 80, warn 76, '
        'submit <=75', () {
      expect(LandmarkSubmissionLogic.maxRestaurantNameLength, 40);
      expect(LandmarkSubmissionLogic.restaurantNameWarnFromLength, 31);
      expect(LandmarkSubmissionLogic.restaurantNameSubmitMaxLength, 30);
      expect(LandmarkSubmissionLogic.maxPhoneLength, 18);
      expect(LandmarkSubmissionLogic.maxWebsiteLength, 80);
      expect(LandmarkSubmissionLogic.websiteWarnFromLength, 76);
      expect(LandmarkSubmissionLogic.websiteSubmitMaxLength, 75);
      expect(LandmarkSubmissionLogic.maxAddressLength, 150);
    });
  });
}
