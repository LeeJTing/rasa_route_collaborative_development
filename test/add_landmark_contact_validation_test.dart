import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

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

  group('website format validation (RFC 3986 + XSS rules)', () {
    test('accepts plain http(s) URLs with a dotted host', () {
      expect(logic.isValidWebsiteFormat('https://example.com'), isTrue);
      expect(logic.isValidWebsiteFormat('http://foodstall.my'), isTrue);
      expect(
        logic.isValidWebsiteFormat('https://example.com/menu?q=1'),
        isTrue,
      );
      // RFC 3986 sub-delims/gen-delims and %XX triplets are all allowed.
      expect(
        logic.isValidWebsiteFormat(
          'https://example.com/menu~2/a-b_c?x=1&y=2#top',
        ),
        isTrue,
      );
      expect(
        logic.isValidWebsiteFormat('https://example.com/path%20with%20spaces'),
        isTrue,
      );
      // The scheme check is case-insensitive, like RFC 3986.
      expect(logic.isValidWebsiteFormat('HTTPS://Example.com'), isTrue);
    });

    test('the scheme is mandatory and must be http(s)', () {
      expect(logic.isValidWebsiteFormat('example.com'), isFalse);
      expect(logic.isValidWebsiteFormat('www.example.com'), isFalse);
      expect(logic.isValidWebsiteFormat('ftp://example.com'), isFalse);
      expect(logic.isValidWebsiteFormat('https://'), isFalse);
      expect(logic.isValidWebsiteFormat(''), isFalse);
    });

    test('blocks script/data schemes and any markup (XSS)', () {
      expect(logic.isValidWebsiteFormat("javascript:alert('Hacked')"), isFalse);
      expect(logic.isValidWebsiteFormat('JaVaScRiPt:alert(1)'), isFalse);
      expect(
        logic.isValidWebsiteFormat('data:text/html;base64,PHNjcmlwdD4='),
        isFalse,
      );
      expect(logic.isValidWebsiteFormat('vbscript:msgbox(1)'), isFalse);
      expect(
        logic.isValidWebsiteFormat(
          'https://example.com/<script>alert(1)</script>',
        ),
        isFalse,
      );
      expect(
        logic.isValidWebsiteFormat('https://example.com/"onmouseover="x'),
        isFalse,
      );
    });

    test('rejects spaces and other non-URL characters', () {
      expect(logic.isValidWebsiteFormat('https://exa mple.com'), isFalse);
      expect(logic.isValidWebsiteFormat('https://example.com/a b'), isFalse);
      expect(logic.isValidWebsiteFormat('https://exa\tmple.com'), isFalse);
      expect(logic.isValidWebsiteFormat('https://example.com/路径'), isFalse);
      expect(logic.isValidWebsiteFormat(r'https://example.com\path'), isFalse);
      // A bare '%' that is not a %XX triplet is not a URL character either.
      expect(logic.isValidWebsiteFormat('https://example.com/a%2'), isFalse);
      expect(logic.isValidWebsiteFormat('https://example.com/%ZZ'), isFalse);
    });

    test('rejects a value containing more than one link', () {
      // Links glued together - no space for the whitespace rule to catch.
      expect(logic.isValidWebsiteFormat('https://a.comhttps://b.com'), isFalse);
      expect(logic.isValidWebsiteFormat('http://a.comhttp://b.com'), isFalse);
      // A second scheme hidden in the path or the query...
      expect(logic.isValidWebsiteFormat('https://a.com/http://b.com'), isFalse);
      expect(
        logic.isValidWebsiteFormat('https://a.com?next=https://b.com'),
        isFalse,
      );
      // ...or another scheme glued straight onto the host.
      expect(logic.isValidWebsiteFormat('https://a.comftp://b.com'), isFalse);
      // Case-insensitive, like the mandatory-scheme rule.
      expect(logic.isValidWebsiteFormat('HTTPS://A.COMHTTPS://B.COM'), isFalse);
      // The single-link helper the field error uses agrees.
      expect(logic.websiteContainsMultipleUrls('https://a.com'), isFalse);
      expect(
        logic.websiteContainsMultipleUrls('https://a.comhttps://b.com'),
        isTrue,
      );
      expect(logic.websiteContainsMultipleUrls('example.com'), isFalse);
    });

    test('rejects credentials, localhost/IP hosts and fake domains', () {
      expect(
        logic.isValidWebsiteFormat('https://user:pass@example.com'),
        isFalse,
      );
      expect(logic.isValidWebsiteFormat('http://localhost'), isFalse);
      expect(logic.isValidWebsiteFormat('http://192.168.1.1'), isFalse);
      expect(logic.isValidWebsiteFormat('http://10.0.0.5'), isFalse);
      expect(
        logic.isValidWebsiteFormat('https://a.b'),
        isFalse,
      ); // TLD too short
      expect(logic.isValidWebsiteFormat('https://example.123'), isFalse);
      expect(logic.isValidWebsiteFormat('https://foo_bar.com'), isFalse);
      expect(logic.isValidWebsiteFormat('https://-bad.com'), isFalse);
      // Gibberish with no TLD at all ("https://not-a-real-site-at-all").
      expect(
        logic.isValidWebsiteFormat('https://not-a-real-site-at-all'),
        isFalse,
      );
    });

    test('caps the link at 2048 characters', () {
      const String prefix = 'https://example.com/';
      final String atLimit =
          prefix +
          'x' * (LandmarkSubmissionLogic.maxWebsiteLength - prefix.length);
      expect(atLimit.length, LandmarkSubmissionLogic.maxWebsiteLength);
      expect(logic.isValidWebsiteFormat(atLimit), isTrue);
      expect(logic.isValidWebsiteFormat('${atLimit}x'), isFalse);
      expect(
        logic.isValidWebsiteFormat(
          'https://example.com/${'x' * LandmarkSubmissionLogic.maxWebsiteLength}',
        ),
        isFalse,
      );
    });
  });

  group('website whitespace + save sanitisation', () {
    test('websiteContainsWhitespace flags spaces and tabs', () {
      expect(logic.websiteContainsWhitespace('https://example.com'), isFalse);
      expect(logic.websiteContainsWhitespace('https://exa mple.com'), isTrue);
      expect(logic.websiteContainsWhitespace('https://exa\tmple.com'), isTrue);
    });

    test('sanitiseWebsiteForSave strips markup, control chars, padding', () {
      expect(
        LandmarkSubmissionLogic.sanitiseWebsiteForSave(
          '  https://example.com  ',
        ),
        'https://example.com',
      );
      expect(
        LandmarkSubmissionLogic.sanitiseWebsiteForSave(
          'https://example.com<script>alert(1)</script>',
        ),
        'https://example.com',
      );
      // For non-script tags only the markup goes; the text stays plain text.
      expect(
        LandmarkSubmissionLogic.sanitiseWebsiteForSave(
          'https://<b>example</b>.com',
        ),
        'https://example.com',
      );
      expect(
        LandmarkSubmissionLogic.sanitiseWebsiteForSave('https://exa\nmple.com'),
        'https://example.com',
      );
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
    test(
      'name: stop 40, warn 31, submit <=30; website: warn 2043, stop 2048',
      () {
        expect(LandmarkSubmissionLogic.maxRestaurantNameLength, 40);
        expect(LandmarkSubmissionLogic.restaurantNameWarnFromLength, 31);
        expect(LandmarkSubmissionLogic.restaurantNameSubmitMaxLength, 30);
        expect(LandmarkSubmissionLogic.maxPhoneLength, 18);
        expect(LandmarkSubmissionLogic.maxWebsiteLength, 2048);
        expect(LandmarkSubmissionLogic.websiteWarnFromLength, 2043);
        expect(LandmarkSubmissionLogic.maxAddressLength, 150);
      },
    );
  });

  group('website warn zone (ViewModel, advisory only)', () {
    test('warning starts at 2043 and typing stops at 2048', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      const String prefix = 'https://example.com/';

      // 2042 characters: quiet, and the link is still valid.
      vm.setRestaurantWebsite(prefix + 'x' * (2042 - prefix.length));
      expect(vm.restaurantWebsiteWarning, isNull);
      expect(vm.restaurantWebsiteError, isNull);

      // 2043: the "stay under" warning appears.
      vm.setRestaurantWebsite(prefix + 'x' * (2043 - prefix.length));
      expect(
        vm.restaurantWebsiteWarning,
        'Website should stay under 2048 characters (currently 2043).',
      );

      // 2048: warning still shown, still no error (valid link at the cap).
      vm.setRestaurantWebsite(prefix + 'x' * (2048 - prefix.length));
      expect(vm.restaurantWebsiteWarning, isNotNull);
      expect(vm.restaurantWebsiteError, isNull);

      // ...and typing stops there - a longer paste is clamped to 2048.
      vm.setRestaurantWebsite(prefix + 'x' * (2048 - prefix.length + 20));
      expect(vm.restaurantWebsite.length, 2048);
      vm.dispose();
    });
  });

  group('website field error (ViewModel)', () {
    test('a multi-link paste gets the one-link message', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      vm.setRestaurantWebsite('https://a.comhttps://b.com');
      expect(
        vm.restaurantWebsiteError,
        'Enter only one website link, e.g. https://example.com.',
      );
      vm.setRestaurantWebsite('https://a.com/http://b.com');
      expect(vm.restaurantWebsiteError, isNotNull);
      // A single link clears the error again.
      vm.setRestaurantWebsite('https://a.com');
      expect(vm.restaurantWebsiteError, isNull);
      vm.dispose();
    });
  });

  group('website link live check (ViewModel)', () {
    test('a well-formed link is probed after typing pauses', () async {
      String? probedUrl;
      final AddLandmarkViewModel vm = AddLandmarkViewModel(
        websiteReachability: (String url) async {
          probedUrl = url;
          return url == 'https://example.org';
        },
      );
      vm.addListener(() {});
      vm.setRestaurantWebsite('https://example.com');
      // Nothing runs while the debounce is still ticking.
      expect(vm.isCheckingWebsiteLink, isFalse);
      expect(vm.websiteLinkStatus, isNull);
      await Future<void>.delayed(
        AddLandmarkViewModel.websiteLinkCheckDelay +
            const Duration(milliseconds: 100),
      );
      expect(probedUrl, 'https://example.com');
      expect(vm.isCheckingWebsiteLink, isFalse);
      expect(vm.websiteLinkUnreachable, isTrue);
      expect(
        vm.websiteLinkStatus,
        "We couldn't open this link. Check the address and try again.",
      );

      // A link that answers clears the note again.
      vm.setRestaurantWebsite('https://example.org');
      await Future<void>.delayed(
        AddLandmarkViewModel.websiteLinkCheckDelay +
            const Duration(milliseconds: 100),
      );
      expect(vm.websiteLinkUnreachable, isFalse);
      expect(vm.websiteLinkStatus, isNull);
      vm.dispose();
    });

    test('a stale probe result is discarded when the field changed', () async {
      final Completer<bool> firstProbe = Completer<bool>();
      final AddLandmarkViewModel vm = AddLandmarkViewModel(
        websiteReachability: (String url) => url == 'https://first.example'
            ? firstProbe.future
            : Future<bool>.value(true),
      );
      vm.addListener(() {});
      vm.setRestaurantWebsite('https://first.example');
      await Future<void>.delayed(
        AddLandmarkViewModel.websiteLinkCheckDelay +
            const Duration(milliseconds: 100),
      );
      expect(vm.isCheckingWebsiteLink, isTrue);
      expect(vm.websiteLinkStatus, 'Checking this link…');

      // Typing resumed before the probe answered...
      vm.setRestaurantWebsite('https://second.example');
      firstProbe.complete(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // ...so its stale failure must not stick.
      expect(vm.websiteLinkUnreachable, isFalse);

      // The second link's own probe then answers fine.
      await Future<void>.delayed(
        AddLandmarkViewModel.websiteLinkCheckDelay +
            const Duration(milliseconds: 100),
      );
      expect(vm.isCheckingWebsiteLink, isFalse);
      expect(vm.websiteLinkUnreachable, isFalse);
      vm.dispose();
    });

    test('malformed input is never probed', () async {
      int probes = 0;
      final AddLandmarkViewModel vm = AddLandmarkViewModel(
        websiteReachability: (String url) async {
          probes++;
          return true;
        },
      );
      vm.addListener(() {});
      vm.setRestaurantWebsite('https://a.comhttps://b.com');
      vm.setRestaurantWebsite('example.com');
      vm.setRestaurantWebsite('');
      await Future<void>.delayed(
        AddLandmarkViewModel.websiteLinkCheckDelay +
            const Duration(milliseconds: 100),
      );
      expect(probes, 0);
      expect(vm.websiteLinkStatus, isNull);
      vm.dispose();
    });

    test(
      'without a form listener the probe never touches the network',
      () async {
        int probes = 0;
        final AddLandmarkViewModel vm = AddLandmarkViewModel(
          websiteReachability: (String url) async {
            probes++;
            return true;
          },
        );
        vm.setRestaurantWebsite('https://example.com');
        await Future<void>.delayed(
          AddLandmarkViewModel.websiteLinkCheckDelay +
              const Duration(milliseconds: 100),
        );
        expect(probes, 0);
        vm.dispose();
      },
    );
  });
}
