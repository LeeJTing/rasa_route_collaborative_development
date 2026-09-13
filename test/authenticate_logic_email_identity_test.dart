import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/authenticate_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/tourist_repository_facade.dart';

/// One mailbox = one account.
///
/// `AuthenticateLogic.canonicalEmail` rewrites the spellings a provider treats
/// as the same mailbox (Gmail dots, `+tag` subaddresses) onto one form, and both
/// `sendEmailOtp` and `verifyEmailOtp` go through it - so every variant signs
/// into a single Supabase user instead of minting a new one.
void main() {
  AuthenticateLogic logicWith(_FakeTouristRepositoryFacade repository) =>
      AuthenticateLogic(repository: repository);

  group('canonicalEmail - verified providers', () {
    const Map<String, String> cases = <String, String>{
      // Gmail: dots and a "+tag" are ignored by Google.
      'john.smith@gmail.com': 'johnsmith@gmail.com',
      'j.o.h.n@gmail.com': 'john@gmail.com',
      'john+news@gmail.com': 'john@gmail.com',
      'john.smith+news@gmail.com': 'johnsmith@gmail.com',
      // googlemail.com is bound to gmail.com - one mailbox, not an alias the
      // user has to configure.
      'john+news@googlemail.com': 'john@gmail.com',
      'john.smith@googlemail.com': 'johnsmith@gmail.com',
      // Subaddressing only: these providers keep the dot significant.
      'john.smith@outlook.com': 'john.smith@outlook.com',
      'john+news@outlook.com': 'john@outlook.com',
      'john.smith@hotmail.com': 'john.smith@hotmail.com',
      'john+news@hotmail.com': 'john@hotmail.com',
      'john+news@live.com': 'john@live.com',
      'john+news@msn.com': 'john@msn.com',
      'john.smith@icloud.com': 'john.smith@icloud.com',
      'john+news@icloud.com': 'john@icloud.com',
      'john+news@me.com': 'john@me.com',
      'john+news@mac.com': 'john@mac.com',
      'john.smith@proton.me': 'john.smith@proton.me',
      'john+news@proton.me': 'john@proton.me',
      'john+news@protonmail.com': 'john@protonmail.com',
      'john.smith@yahoo.com': 'john.smith@yahoo.com',
      'john+news@yahoo.com': 'john@yahoo.com',
      'john+news@ymail.com': 'john@ymail.com',
    };

    cases.forEach((String input, String expected) {
      test('$input -> $expected', () {
        expect(
          logicWith(_FakeTouristRepositoryFacade()).canonicalEmail(input),
          expected,
        );
      });
    });
  });

  group('canonicalEmail - unknown domains are untouched', () {
    // The rule that keeps custom domains safe: a domain we have not verified is
    // left exactly as typed, so nothing legitimate can be merged or blocked.
    const List<String> untouched = <String>[
      'tourist@example.com',
      'john.smith@example.com',
      'john+news@example.com',
      'a.b+tag@mycompany.com.my',
    ];

    for (final String email in untouched) {
      test(email, () {
        expect(
          logicWith(_FakeTouristRepositoryFacade()).canonicalEmail(email),
          email,
        );
      });
    }
  });

  group('canonicalEmail - shape', () {
    test('trims and lowercases', () {
      expect(
        logicWith(
          _FakeTouristRepositoryFacade(),
        ).canonicalEmail('  JoHn@Gmail.com  '),
        'john@gmail.com',
      );
    });

    test('never emits an address with nothing before the @', () {
      // The safety rail: whatever happens, the rewrite cannot produce an
      // unsendable address.
      final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

      expect(logic.canonicalEmail('@gmail.com'), '@gmail.com');
      expect(logic.canonicalEmail('no-at-sign'), 'no-at-sign');
    });
  });

  group('isSaltedEmail', () {
    test('true only when the mailbox rewrite actually changes the address', () {
      final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

      expect(logic.isSaltedEmail('john.smith@gmail.com'), isTrue);
      expect(logic.isSaltedEmail('john+news@gmail.com'), isTrue);
      expect(logic.isSaltedEmail('john.smith@outlook.com'), isFalse);
      expect(logic.isSaltedEmail('tourist@example.com'), isFalse);
      // Case alone is not "salted" - the screen should not explain a rewrite
      // the tourist cannot see.
      expect(logic.isSaltedEmail('JoHn@Gmail.com'), isFalse);
      expect(logic.isSaltedEmail('   '), isFalse);
    });
  });

  group('emailError - new ASCII rule', () {
    final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

    test('rejects a non-ASCII local part', () {
      expect(
        logic.emailError('用户@example.com'),
        AuthenticateLogic.emailNonAsciiMessage,
      );
    });

    test('rejects a non-ASCII domain', () {
      expect(
        logic.emailError('user@例え.jp'),
        AuthenticateLogic.emailNonAsciiMessage,
      );
      expect(
        logic.emailError('مستخدم@example.com'),
        AuthenticateLogic.emailNonAsciiMessage,
      );
    });

    test('rejects an invisible character smuggled into an ASCII address', () {
      // U+200B (zero-width space) renders as nothing, so this address looks
      // identical to user@example.com while being a different string.
      expect(
        logic.emailError('user\u200B@example.com'),
        AuthenticateLogic.emailNonAsciiMessage,
      );
    });

    test('a plain space still gets its own, clearer message', () {
      expect(
        logic.emailError('user name@example.com'),
        AuthenticateLogic.emailSpaceMessage,
      );
    });

    test('ASCII addresses are unaffected', () {
      expect(logic.emailError('user@example.com'), isNull);
      expect(logic.emailError('first.last+tag@example.com'), isNull);
    });
  });

  group('emailError - the house rule, on every domain', () {
    final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

    test('allows letters, digits and the four safe symbols', () {
      const List<String> legal = <String>[
        'user@example.com',
        'first.last@example.com',
        'first_last@example.com',
        'first-last@example.com',
        'first+tag@example.com',
        'a_b-c.d+e@example.com',
      ];

      for (final String email in legal) {
        expect(logic.emailError(email), isNull, reason: email);
      }
    });

    test('rejects the rest of the RFC `atext` symbols on an unlisted domain', () {
      // Strictly narrower than RFC 5322 on purpose. These are legal dot-atoms,
      // but no consumer provider issues them and each one is extra escaping for
      // every tool that later touches the address.
      const List<String> rejected = <String>[
        "o'brien@example.com",
        'first!last@example.com',
        'user#tag@example.com',
        r'cash$tag@example.com',
        'per%cent@example.com',
        'and&more@example.com',
        'star*fish@example.com',
        'first/last@example.com',
        'a=b@example.com',
        'why?what@example.com',
        'caret^hat@example.com',
        r'back`tick@example.com',
        'a{b}c@example.com',
        'user|name@example.com',
        'user~name@example.com',
      ];

      for (final String email in rejected) {
        expect(
          // The generic message: this is OUR rule, not a fact about example.com,
          // so it must not claim the domain forbids the character.
          logic.emailError(email),
          AuthenticateLogic.emailInvalidCharMessage,
          reason: email,
        );
      }
    });

    test('characters outside the dot-atom are rejected the same way', () {
      // `"` was never `atext`, and a quoted-string local part (`"john doe"@…`)
      // is RFC-legal but issued by nobody.
      const List<String> rejected = <String>[
        'jo"hn@example.com',
        'user,name@example.com',
        'user[name@example.com',
        r'user\name@example.com',
        'user;name@example.com',
        'user<name@example.com',
      ];

      for (final String email in rejected) {
        expect(
          logic.emailError(email),
          AuthenticateLogic.emailInvalidCharMessage,
          reason: email,
        );
      }
    });

    test('a name never starts or ends with a symbol - on any domain', () {
      const List<String> rejected = <String>[
        '+tag@example.com',
        '-john@example.com',
        '_john@example.com',
        'john+@example.com',
        'john-@example.com',
        'john_@example.com',
      ];

      for (final String email in rejected) {
        expect(
          logic.emailError(email),
          AuthenticateLogic.emailLocalEdgeMessage,
          reason: email,
        );
      }
    });

    test('dots are still separators, never repeats', () {
      expect(
        logic.emailError('.user@example.com'),
        AuthenticateLogic.emailDotMessage,
      );
      expect(
        logic.emailError('user.@example.com'),
        AuthenticateLogic.emailDotMessage,
      );
      expect(
        logic.emailError('user..name@example.com'),
        AuthenticateLogic.emailDotMessage,
      );
    });
  });

  group('emailError - verified provider charsets', () {
    final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

    test('Gmail takes letters, numbers and dots only', () {
      expect(logic.emailError('johndoe@gmail.com'), isNull);

      // Neither could ever be a Gmail username - the old generic rule accepted
      // both, so the failure only showed up later at the send.
      expect(
        logic.emailError('john_doe@gmail.com'),
        AuthenticateLogic.localCharNotAllowedMessage('gmail.com', '_'),
      );
      expect(
        logic.emailError('john-doe@gmail.com'),
        AuthenticateLogic.localCharNotAllowedMessage('gmail.com', '-'),
      );
    });

    test('a verified provider never starts or ends with a symbol', () {
      expect(
        logic.emailError('+tag@gmail.com'),
        AuthenticateLogic.emailLocalEdgeMessage,
      );
      expect(
        logic.emailError('john+@gmail.com'),
        AuthenticateLogic.emailLocalEdgeMessage,
      );
    });

    test('Microsoft is wider than Gmail but still narrower than the RFC', () {
      expect(logic.emailError('john_doe@outlook.com'), isNull);
      expect(logic.emailError('john-doe@hotmail.com'), isNull);
      expect(
        logic.emailError("john!doe@outlook.com"),
        AuthenticateLogic.localCharNotAllowedMessage('outlook.com', '!'),
      );
    });

    test('Yahoo is held to its own set', () {
      expect(logic.emailError('johndoe@yahoo.com'), isNull);
      expect(logic.emailError('john.doe@ymail.com'), isNull);
      expect(
        logic.emailError('john!doe@yahoo.com'),
        AuthenticateLogic.localCharNotAllowedMessage('yahoo.com', '!'),
      );
    });

    test(
      'the same character gets OUR generic message on an unlisted domain',
      () {
        // Same rejection, different reason: here it is the app's house rule, so
        // the message must not claim example.com forbids it.
        expect(
          logic.emailError('john!doe@example.com'),
          AuthenticateLogic.emailInvalidCharMessage,
        );
        // The four safe symbols pass anywhere.
        expect(logic.emailError('john_doe@mycompany.com.my'), isNull);
        expect(logic.emailError('john-doe+tag@mycompany.com.my'), isNull);
      },
    );
  });

  group('emailError - salting blocked at the field', () {
    final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

    test('a "+tag" alias is refused on every subaddressing provider', () {
      // "+" itself is a legal, familiar symbol, so the message has to say that
      // it is the salted SPELLING being refused - and name the address to use.
      expect(
        logic.emailError('johndoe+news@gmail.com'),
        AuthenticateLogic.aliasNotAllowedMessage('johndoe@gmail.com'),
      );
      expect(
        logic.emailError('johndoe+news@googlemail.com'),
        AuthenticateLogic.aliasNotAllowedMessage('johndoe@gmail.com'),
      );
      expect(
        logic.emailError('john+news@outlook.com'),
        AuthenticateLogic.aliasNotAllowedMessage('john@outlook.com'),
      );
      expect(
        logic.emailError('john+news@hotmail.com'),
        AuthenticateLogic.aliasNotAllowedMessage('john@hotmail.com'),
      );
      expect(
        logic.emailError('john+news@icloud.com'),
        AuthenticateLogic.aliasNotAllowedMessage('john@icloud.com'),
      );
      expect(
        logic.emailError('john+news@proton.me'),
        AuthenticateLogic.aliasNotAllowedMessage('john@proton.me'),
      );
      expect(
        logic.emailError('john+news@protonmail.com'),
        AuthenticateLogic.aliasNotAllowedMessage('john@protonmail.com'),
      );
      expect(
        logic.emailError('john+news@yahoo.com'),
        AuthenticateLogic.aliasNotAllowedMessage('john@yahoo.com'),
      );
      expect(
        logic.emailError('john+news@live.com'),
        AuthenticateLogic.aliasNotAllowedMessage('john@live.com'),
      );
    });

    test('a dotted Gmail name is refused', () {
      expect(
        logic.emailError('john.smith@gmail.com'),
        AuthenticateLogic.dotsIgnoredMessage('johnsmith@gmail.com'),
      );
      // Case does not hide it, and googlemail.com is the same mailbox. (The
      // username has to clear the 6-character Gmail rule before the dots are
      // what gets reported - see the length group below.)
      expect(
        logic.emailError('J.o.h.ndoe@GoogleMail.com'),
        AuthenticateLogic.dotsIgnoredMessage('johndoe@gmail.com'),
      );
    });

    test('both tricks at once resolve in one edit', () {
      // The suggestion is the fully canonical address, so clearing the dots and
      // the tag in one go is what fixes it.
      expect(
        logic.emailError('john.smith+news@gmail.com'),
        AuthenticateLogic.aliasNotAllowedMessage('johnsmith@gmail.com'),
      );
    });

    test('dots stay significant for every provider except Gmail', () {
      // Only Gmail ignores dots, so a dotted name on these is a real, distinct
      // address and must NOT be refused.
      expect(logic.emailError('john.smith@outlook.com'), isNull);
      expect(logic.emailError('john.smith@hotmail.com'), isNull);
      expect(logic.emailError('john.smith@live.com'), isNull);
      expect(logic.emailError('john.smith@icloud.com'), isNull);
      expect(logic.emailError('john.smith@me.com'), isNull);
      expect(logic.emailError('john.smith@proton.me'), isNull);
      expect(logic.emailError('john.smith@protonmail.com'), isNull);
      expect(logic.emailError('john.smith@yahoo.com'), isNull);
      expect(logic.emailError('john.smith@ymail.com'), isNull);
    });

    test('an unlisted domain keeps its dots and aliases', () {
      // We cannot judge a custom domain, so neither rule is applied to it.
      expect(logic.emailError('first.last@example.com'), isNull);
      expect(logic.emailError('first+tag@example.com'), isNull);
      expect(logic.emailError('first.last+tag@mycompany.com.my'), isNull);
    });

    test('a malformed address is reported before the salting', () {
      // Suggesting the dot-less spelling would be wrong for these, so the shape
      // problem wins: neither "abc" nor "john_doe" can be a Gmail username.
      expect(
        logic.emailError('a.b.c@gmail.com'),
        AuthenticateLogic.localLengthMessage('gmail.com', 6, 30),
      );
      expect(
        logic.emailError('john_doe@gmail.com'),
        AuthenticateLogic.localCharNotAllowedMessage('gmail.com', '_'),
      );
      expect(
        logic.emailError('+tag@gmail.com'),
        AuthenticateLogic.emailLocalEdgeMessage,
      );
    });
  });

  group('emailError - name length per provider', () {
    final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

    String gmailLength() =>
        AuthenticateLogic.localLengthMessage('gmail.com', 6, 30);

    test('Gmail rejects a local part shorter than 6 characters', () {
      expect(logic.emailError('a@gmail.com'), gmailLength());
      expect(logic.emailError('abcde@gmail.com'), gmailLength());
      // googlemail.com follows the same window, and the message names the domain
      // the tourist actually typed.
      expect(
        logic.emailError('ab@googlemail.com'),
        AuthenticateLogic.localLengthMessage('googlemail.com', 6, 30),
      );
    });

    test('Gmail measures the username, not the dots', () {
      // Google ignores the dots, so this username is "abc" - 3 characters - even
      // though 5 characters were typed. The length problem is reported first: the
      // dot-less spelling we would suggest is invalid too.
      expect(logic.emailError('a.b.c@gmail.com'), gmailLength());
    });

    test('a long-enough name is then judged on its salting, not its length', () {
      // The same username once the dots go - 6 characters, so long enough - so
      // what gets refused is the dotting itself.
      expect(
        logic.emailError('a.b.cdef@gmail.com'),
        AuthenticateLogic.dotsIgnoredMessage('abcdef@gmail.com'),
      );
      expect(
        logic.emailError('abcdef+news@gmail.com'),
        AuthenticateLogic.aliasNotAllowedMessage('abcdef@gmail.com'),
      );
    });

    test('rejects a Gmail local part longer than 30 characters', () {
      expect(logic.emailError('${'a' * 31}@gmail.com'), gmailLength());
      expect(logic.emailError('${'a' * 30}@gmail.com'), isNull);
    });

    test('iCloud issues 3-20 characters, and counts the dots', () {
      final String icloudLength = AuthenticateLogic.localLengthMessage(
        'icloud.com',
        3,
        20,
      );
      expect(logic.emailError('ab@icloud.com'), icloudLength);
      expect(logic.emailError('${'a' * 21}@icloud.com'), icloudLength);
      expect(logic.emailError('abc@icloud.com'), isNull);
      expect(logic.emailError('${'a' * 20}@icloud.com'), isNull);
      // Unlike Gmail the dots are characters, so they push the name past the
      // window rather than being ignored.
      expect(logic.emailError('${'a' * 19}.b@icloud.com'), icloudLength);
    });

    test('Apple legacy domains follow iCloud', () {
      expect(
        logic.emailError('ab@me.com'),
        AuthenticateLogic.localLengthMessage('me.com', 3, 20),
      );
      expect(
        logic.emailError('ab@mac.com'),
        AuthenticateLogic.localLengthMessage('mac.com', 3, 20),
      );
      expect(logic.emailError('johndoe@me.com'), isNull);
      expect(logic.emailError('johndoe@mac.com'), isNull);
    });

    test('Microsoft issues 1-64 - the same as the RFC cap', () {
      expect(logic.emailError('a@outlook.com'), isNull);
      expect(logic.emailError('ab@hotmail.com'), isNull);
      expect(logic.emailError('${'a' * 64}@live.com'), isNull);
      // 65 hits the global cap first, so the message is the generic one.
      expect(
        logic.emailError('${'a' * 65}@outlook.com'),
        AuthenticateLogic.emailTooLongMessage,
      );
    });

    test('Proton issues 1-40', () {
      expect(logic.emailError('a@proton.me'), isNull);
      expect(logic.emailError('${'a' * 40}@proton.me'), isNull);
      expect(logic.emailError('${'a' * 40}@protonmail.com'), isNull);
      expect(
        logic.emailError('${'a' * 41}@proton.me'),
        AuthenticateLogic.localLengthMessage('proton.me', 1, 40),
      );
    });

    test('Yahoo issues 1-32 and must start with a letter', () {
      expect(logic.emailError('johndoe@yahoo.com'), isNull);
      expect(logic.emailError('${'j' * 32}@yahoo.com'), isNull);
      expect(
        logic.emailError('${'j' * 33}@yahoo.com'),
        AuthenticateLogic.localLengthMessage('yahoo.com', 1, 32),
      );
      expect(
        logic.emailError('${'j' * 33}@ymail.com'),
        AuthenticateLogic.localLengthMessage('ymail.com', 1, 32),
      );

      // A digit start is the stricter rule on top of the shared edge rule.
      expect(
        logic.emailError('1johndoe@yahoo.com'),
        AuthenticateLogic.localLetterStartMessage('yahoo.com'),
      );
      expect(
        logic.emailError('1johndoe@ymail.com'),
        AuthenticateLogic.localLetterStartMessage('ymail.com'),
      );
      // The same name on a provider without that rule is fine, and a leading
      // SYMBOL is still the edge rule's job.
      expect(logic.emailError('1johndoe@outlook.com'), isNull);
      expect(
        logic.emailError('-johndoe@yahoo.com'),
        AuthenticateLogic.emailLocalEdgeMessage,
      );
    });

    test('a domain with no verified window is not length-checked', () {
      // Every custom domain: the 64-character RFC cap still applies, but nothing
      // tighter is asserted about them.
      expect(logic.emailError('a@mycompany.com.my'), isNull);
      expect(logic.emailError('${'a' * 64}@mycompany.com.my'), isNull);
      expect(
        logic.emailError('${'a' * 65}@mycompany.com.my'),
        AuthenticateLogic.emailTooLongMessage,
      );
    });
  });

  group('emailError - two symbols in a row', () {
    final AuthenticateLogic logic = logicWith(_FakeTouristRepositoryFacade());

    test('Proton refuses every pair, not just dots', () {
      // The dot-atom rule only catches "..", and only because the RFC forbids it.
      // "--", "._" and "-." are legal dot-atoms everywhere else.
      for (final String pair in <String>['--', '._', '-.', '_--']) {
        expect(
          logic.emailError('john${pair}doe@proton.me'),
          AuthenticateLogic.consecutiveSpecialsMessage('proton.me'),
          reason: pair,
        );
        expect(
          logic.emailError('john${pair}doe@protonmail.com'),
          AuthenticateLogic.consecutiveSpecialsMessage('protonmail.com'),
          reason: pair,
        );
      }
    });

    test('a single symbol is still fine on Proton', () {
      expect(logic.emailError('john-doe@proton.me'), isNull);
      expect(logic.emailError('john_doe@proton.me'), isNull);
      expect(logic.emailError('john.doe@proton.me'), isNull);
    });

    test('two dots are refused on EVERY domain, as a dot-atom violation', () {
      // Illegal RFC-wide, so it does not need a provider entry - and it keeps
      // its own, more precise message.
      expect(
        logic.emailError('john..doe@example.com'),
        AuthenticateLogic.emailDotMessage,
      );
      expect(
        logic.emailError('john..doe@proton.me'),
        AuthenticateLogic.emailDotMessage,
      );
    });

    test('every other provider still accepts a pair', () {
      // Microsoft does not have the rule, and neither does an unlisted domain -
      // blocking it there would refuse addresses those systems really do issue.
      expect(logic.emailError('john--doe@outlook.com'), isNull);
      expect(logic.emailError('john-.doe@hotmail.com'), isNull);
      expect(logic.emailError('john--doe@example.com'), isNull);
    });

    test('the character and edge rules still win over the pair rule', () {
      // A symbol the provider cannot use is reported as itself, not as a pair.
      expect(
        logic.emailError('john!!doe@proton.me'),
        AuthenticateLogic.localCharNotAllowedMessage('proton.me', '!'),
      );
      expect(
        logic.emailError('+tag@proton.me'),
        AuthenticateLogic.emailLocalEdgeMessage,
      );
    });
  });

  group('sendEmailOtp uses the mailbox identity', () {
    test(
      'a salted spelling is refused before it reaches the repository',
      () async {
        // The field blocks it first; this is the logic-layer guard behind that
        // guard, so a stale pending email or a deep link cannot slip one past
        // the screen and create the second account the block exists to prevent.
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade();

        await expectLater(
          logicWith(repository).sendEmailOtp('  John.Smith+news@Gmail.com  '),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message,
              'message',
              AuthenticateLogic.aliasNotAllowedMessage('johnsmith@gmail.com'),
            ),
          ),
        );

        expect(repository.sentEmails, isEmpty);
        expect(repository.recordedOtpSends, isEmpty);
      },
    );

    test(
      'an unknown domain is sent exactly as typed (plus case/trim)',
      () async {
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade();

        await logicWith(repository).sendEmailOtp(' John.Smith@Example.com ');

        expect(repository.sentEmails, <String>['john.smith@example.com']);
      },
    );

    test('the 3-per-10 gate is keyed on the mailbox identity', () async {
      // Salting no longer reaches this gate - the field refuses it - but case is
      // still folded, so `JohnDoe@Gmail.com` and `johndoe@gmail.com` share one
      // bucket instead of getting one each.
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(
            otpSendTimesResult: List<DateTime>.generate(
              AuthenticateLogic.otpSendRateLimit,
              (_) => DateTime.now(),
            ),
          );

      await expectLater(
        logicWith(repository).sendEmailOtp('  JohnDoe@Gmail.com  '),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            AuthenticateLogic.otpSendRateLimitMessage,
          ),
        ),
      );

      // Queried under the identity, not the spelling that was typed.
      expect(repository.otpSendTimesCalls, <String>['johndoe@gmail.com']);
      expect(repository.sentEmails, isEmpty);
    });

    test('a malformed address is still rejected before the rewrite', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();

      await expectLater(
        logicWith(repository).sendEmailOtp('a@gmail.com'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            AuthenticateLogic.localLengthMessage('gmail.com', 6, 30),
          ),
        ),
      );
      expect(repository.sentEmails, isEmpty);
    });
  });

  group('verifyEmailOtp uses the mailbox identity', () {
    test('the code is checked against the same form the send used', () async {
      // If send and verify disagreed, the code mailed to the canonical address
      // would never verify. Case is folded on both sides.
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();

      await logicWith(
        repository,
      ).verifyEmailOtp(email: ' JohnDoe@Gmail.com ', token: ' 123456 ');

      expect(repository.verifyCalls, <String>['johndoe@gmail.com']);
    });

    test('a salted spelling cannot be verified through either', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();

      await expectLater(
        logicWith(
          repository,
        ).verifyEmailOtp(email: 'john.smith@gmail.com', token: '123456'),
        throwsA(isA<ArgumentError>()),
      );

      expect(repository.verifyCalls, isEmpty);
    });
  });

  group('device-wide resend cooldown', () {
    test(
      'blocks a send on the same device, whichever address is asked for',
      () async {
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade(
              otpLastDeviceSendAtResult: DateTime.now(),
            );

        await expectLater(
          // A brand-new address, no per-address history at all - switching
          // accounts used to buy a fresh allowance.
          logicWith(repository).sendEmailOtp('someone-else@example.com'),
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.message,
              'message',
              AuthenticateLogic.otpDeviceCooldownMessage,
            ),
          ),
        );

        expect(repository.sentEmails, isEmpty);
        expect(repository.otpSendTimesCalls, isEmpty);
      },
    );

    test('allows a send once the cooldown has elapsed', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(
            otpLastDeviceSendAtResult: DateTime.now().subtract(
              AuthenticateLogic.otpDeviceCooldown + const Duration(seconds: 1),
            ),
          );

      await logicWith(repository).sendEmailOtp('tourist@example.com');

      expect(repository.sentEmails, <String>['tourist@example.com']);
    });

    test('the per-address cap still applies after the cooldown', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(
            otpLastDeviceSendAtResult: DateTime.now().subtract(
              AuthenticateLogic.otpDeviceCooldown + const Duration(seconds: 1),
            ),
            otpSendTimesResult: List<DateTime>.generate(
              AuthenticateLogic.otpSendRateLimit,
              (_) => DateTime.now(),
            ),
          );

      await expectLater(
        logicWith(repository).sendEmailOtp('tourist@example.com'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            AuthenticateLogic.otpSendRateLimitMessage,
          ),
        ),
      );
    });
  });
}

/// Fakes the repository facade - the only seam `AuthenticateLogic` knows.
class _FakeTouristRepositoryFacade extends TouristRepositoryFacade {
  _FakeTouristRepositoryFacade({
    this.otpSendTimesResult = const <DateTime>[],
    this.otpLastDeviceSendAtResult,
  });

  /// Pre-seeded per-address send history.
  List<DateTime> otpSendTimesResult;

  /// When this device last sent a code; null means "never".
  DateTime? otpLastDeviceSendAtResult;

  final List<String> sentEmails = <String>[];
  final List<String> verifyCalls = <String>[];
  final List<String> recordedOtpSends = <String>[];
  final List<String> otpSendTimesCalls = <String>[];

  @override
  Future<void> sendEmailOtp(String email) async => sentEmails.add(email);

  @override
  Future<List<DateTime>> otpSendTimes(String email) async {
    otpSendTimesCalls.add(email);
    return otpSendTimesResult;
  }

  @override
  Future<void> recordOtpSend(String email) async => recordedOtpSends.add(email);

  @override
  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifyCalls.add(email);
    return null;
  }

  @override
  DateTime? get otpLastDeviceSendAt => otpLastDeviceSendAtResult;
}
