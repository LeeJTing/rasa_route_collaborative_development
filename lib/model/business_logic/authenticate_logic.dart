import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/auth_session.dart';
import '../../domain_model/tourist.dart';
import '../repositories/tourist_repository_facade.dart';

/// Sign-in, sign-up and OTP rules.
///
/// A business-logic class knows exactly one thing below it: a repository
/// facade. It never sees individual repositories, shared clients,
/// Supabase SDK or Flutter.
class AuthenticateLogic {
  AuthenticateLogic({@visibleForTesting TouristRepositoryFacade? repository})
    : repository = repository ?? TouristRepositoryFacade();

  final TouristRepositoryFacade repository;

  /// How many OTP emails one address may receive in [otpSendRateWindow] - the
  /// Grab-style cap that keeps a tourist from hammering "Send OTP" (they can
  /// cancel the OTP screen and request again from the login screen, but only
  /// this many times per window).
  static const int otpSendRateLimit = 3;

  /// The rolling window for [otpSendRateLimit].
  static const Duration otpSendRateWindow = Duration(minutes: 10);

  /// Shown when the same email has already received [otpSendRateLimit] codes
  /// inside [otpSendRateWindow].
  static const String otpSendRateLimitMessage =
      'Too many attempts, please try again later.';

  /// How long this DEVICE must wait between OTP sends, whichever address is
  /// asked for.
  ///
  /// [otpSendRateLimit] is per address, so a tourist could side-step it by
  /// switching accounts on the same handset. This one is device-wide, so doing
  /// that gains nothing. (A per-IP cap would need the server - Supabase's own
  /// rate limits - since the client cannot see the caller's address.)
  static const Duration otpDeviceCooldown = Duration(seconds: 60);

  /// Shown when [otpDeviceCooldown] has not elapsed yet.
  static const String otpDeviceCooldownMessage =
      'Please wait a minute before requesting another code.';

  // Short, cause-specific messages from [emailError] - one reason per line so
  // the login screen can tell the tourist WHAT is wrong, not just that it is.

  static const String emailTooLongMessage = 'Email is too long.';
  static const String emailMissingAtMessage = "Email needs an '@'.";
  static const String emailTooManyAtMessage = "Email can have only one '@'.";
  static const String emailMissingNameMessage =
      "Email needs a name before the '@'.";
  static const String emailMissingDomainMessage =
      "Email needs a domain after the '@'.";
  static const String emailSpaceMessage = "Email can't contain spaces.";
  static const String emailDotMessage =
      "Email can't start, end, or double a dot.";
  static const String emailInvalidCharMessage =
      "Email has characters that aren't allowed.";
  static const String emailNoTldMessage =
      'Email needs a domain like example.com.';
  static const String emailTldBadMessage = 'Email domain looks incomplete.';
  static const String emailInvalidDomainMessage =
      'Email domain has invalid characters.';

  /// Shown when the address holds anything outside printable ASCII.
  ///
  /// Internationalized (SMTPUTF8) addresses are not supported yet, and this
  /// doubles as the guard against invisible characters: zero-width joiners and
  /// bidi overrides are all non-ASCII, and one embedded in an address makes it
  /// render exactly like a different address.
  static const String emailNonAsciiMessage =
      'Email can only use English letters, numbers and common symbols.';

  /// Shown when a name falls outside the length window its provider issues -
  /// Gmail's 6-30, iCloud's 3-20, Yahoo's 1-32.
  static String localLengthMessage(String domain, int min, int max) =>
      'Email addresses at $domain need $min-$max characters before the "@".';

  /// Shown when a provider insists the name starts with a letter, not a digit.
  static String localLetterStartMessage(String domain) =>
      'Email addresses at $domain must start with a letter.';

  /// Shown when a provider refuses two symbols in a row (`..`, `--`, `._`, …).
  ///
  /// Kept separate from [emailDotMessage] because only `..` is illegal RFC-wide;
  /// a double hyphen is a per-provider rule, and telling someone their dots are
  /// wrong when the problem is `--` would be nonsense.
  static String consecutiveSpecialsMessage(String domain) =>
      'Email addresses at $domain cannot use two symbols in a row.';

  /// Shown when a name begins or ends with a symbol (`+tag@gmail.com`,
  /// `-john@outlook.com`, `user+@example.com`). No provider issues one, so this
  /// applies to every domain, unlike the provider-specific characters below.
  static const String emailLocalEdgeMessage =
      'Email cannot start or end with a symbol.';

  /// Shown when a VERIFIED provider cannot actually issue the address - e.g.
  /// `_` in a Gmail username. Our own house rule uses the generic
  /// [emailInvalidCharMessage] instead, because claiming a custom domain
  /// forbids a character would be a guess about that domain.
  static String localCharNotAllowedMessage(String domain, String char) =>
      'Email addresses at $domain cannot use "$char".';

  /// Shown when a `+tag` alias is typed on a provider that subaddresses.
  ///
  /// Deliberately NOT [localCharNotAllowedMessage]: `+` is a legal and common
  /// symbol, so the message has to say that it is the *salted spelling* being
  /// refused - and hand over the address to use instead.
  static String aliasNotAllowedMessage(String suggestion) =>
      '"+" aliases are not supported. Use "$suggestion" instead.';

  /// Shown when a dotted Gmail name is typed.
  ///
  /// Gmail delivers every dotting of a username to the same mailbox, so the dots
  /// cannot buy a second account - and accepting them would store an address the
  /// tourist never typed. The suggestion is the exact spelling to use.
  static String dotsIgnoredMessage(String suggestion) =>
      'Gmail ignores dots. Use "$suggestion" instead.';

  // --------------------------------------------------------------------------
  // Local-part characters
  //
  // One house rule for every domain we have NOT verified: letters, digits and
  // [_defaultLocalSpecials]. RFC 5322's `atext` grammar allows far more
  // (`o'brien@…`, `first!last@…`, `a|b@…`, backticks, braces), but no consumer
  // provider issues those, and every one of them has to be escaped correctly by
  // everything that later touches the address - CSV exports, mail headers, HTML
  // templates. Narrowing the surface is not the injection fix (parameterised
  // queries and escaping are) - it is declining to carry input nothing needs.
  //
  // A VERIFIED provider still overrides with its own set, because there the
  // narrower rule is a fact about that provider rather than our preference -
  // which is also what lets the message name the provider.
  // --------------------------------------------------------------------------

  /// The symbols accepted on every domain: the dot separator, underscore,
  /// hyphen and the `+` alias separator.
  ///
  /// `%` is the one further symbol with any legitimacy (legacy gateway
  /// addresses such as `user%domain@relay`); it is left out because those are
  /// effectively extinct.
  static const String _defaultLocalSpecials = '._-+';

  /// The symbols each VERIFIED provider allows on top of letters and digits.
  ///
  /// Scope: the globally dominant consumer providers and the domains each of
  /// them issues. Everything else - Tuta, Zoho, country Yahoo domains, every
  /// corporate domain - is deliberately unlisted and falls back to the house
  /// rule, which is why the list has to stay honest and short.
  ///
  /// An entry that matches [_defaultLocalSpecials] still earns its place: it
  /// turns our house rule into a statement about that provider, so a rejection
  /// there can name the domain instead of returning the generic message.
  static const Map<String, String> _localSpecialsByDomain = <String, String>{
    // Gmail: letters and numbers only, plus the dot separators. `+` is kept in
    // the set so the salting rule below reports the alias, not the character.
    'gmail.com': '.+',
    'googlemail.com': '.+',
    // Microsoft consumer mail: periods, hyphens and underscores.
    'outlook.com': '.-_+',
    'hotmail.com': '.-_+',
    'live.com': '.-_+',
    'msn.com': '.-_+',
    // Apple: periods, underscores and hyphens.
    'icloud.com': '._-+',
    'me.com': '._-+',
    'mac.com': '._-+',
    // Proton.
    'protonmail.com': '._-+',
    'proton.me': '._-+',
    // Yahoo: periods, underscores and hyphens.
    'yahoo.com': '._-+',
    'ymail.com': '._-+',
  };

  // --------------------------------------------------------------------------
  // Name shape per provider: symbol pairs and length
  //
  // Both are narrower than the RFC and both BLOCK a real address when the entry
  // is wrong, so each line is a verification task and an unlisted domain is
  // simply not checked.
  // --------------------------------------------------------------------------

  /// Providers that refuse a name with two symbols in a row (`..`, `--`, `._`,
  /// `-.`, …).
  ///
  /// Only `..` is rejected for EVERY domain, because RFC 5322's dot-atom forbids
  /// it. Everything else is a provider rule: `john--doe@…` is a legal dot-atom,
  /// and a custom domain's admin is free to have created one, so blocking it
  /// everywhere would refuse real addresses.
  static const Set<String> _noConsecutiveSpecialsDomains = <String>{
    // Proton's documented username rule.
    'protonmail.com',
    'proton.me',
    // Reported for Apple as well, but not confirmed - add icloud.com, me.com and
    // mac.com here only once someone checks.
    // Microsoft (outlook/hotmail/live/msn) allows consecutive symbols, so it
    // must NOT be added.
  };

  /// The name-length window each provider issues, as `[min, max]`.
  ///
  /// A domain with no entry has no verified window here, so only the RFC's own
  /// 64-character cap applies.
  static const Map<String, List<int>> _nameLengthByDomain = <String, List<int>>{
    // Google: 6-30. Dots and the `+tag` suffix do not count towards it.
    'gmail.com': <int>[6, 30],
    'googlemail.com': <int>[6, 30],
    // Apple: 3-20. Dots ARE characters here, so they count.
    'icloud.com': <int>[3, 20],
    'me.com': <int>[3, 20],
    'mac.com': <int>[3, 20],
    // Microsoft: 1-64, which is exactly the RFC's own cap - so the global length
    // check normally reports first and this entry only documents the rule.
    'outlook.com': <int>[1, 64],
    'hotmail.com': <int>[1, 64],
    'live.com': <int>[1, 64],
    'msn.com': <int>[1, 64],
    // Proton: 1-40.
    'protonmail.com': <int>[1, 40],
    'proton.me': <int>[1, 40],
    // Yahoo: 1-32 (and a letter start - see [_letterStartDomains]).
    'yahoo.com': <int>[1, 32],
    'ymail.com': <int>[1, 32],
  };

  /// Providers whose names must begin with a LETTER, not a digit.
  ///
  /// The edge rule already stops a symbol in that position; this is the stricter
  /// case on top of it, so `1johndoe@yahoo.com` is refused while
  /// `1johndoe@outlook.com` is fine.
  static const Set<String> _letterStartDomains = <String>{
    'yahoo.com',
    'ymail.com',
    // Reported for Apple as well, but not confirmed - add icloud.com, me.com and
    // mac.com here only once someone checks.
  };

  /// True when [char] is a single ASCII letter.
  static bool _isAsciiLetter(String char) {
    final int unit = char.codeUnitAt(0);
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }

  /// True when [char] is a single ASCII letter or digit.
  static bool _isAsciiLetterOrDigit(String char) {
    final int unit = char.codeUnitAt(0);
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A);
  }

  /// True when two symbols sit next to each other in [local].
  ///
  /// Dots count as symbols, so `._` and `-.` are found too - `..` never reaches
  /// this check, having already been rejected as a dot-atom violation everywhere.
  static bool _hasConsecutiveSpecials(String local) {
    for (int index = 1; index < local.length; index++) {
      if (!_isAsciiLetterOrDigit(local[index - 1]) &&
          !_isAsciiLetterOrDigit(local[index])) {
        return true;
      }
    }
    return false;
  }

  /// Why [local] falls outside [domain]'s name-length window, or null when it
  /// fits or the domain has no verified window.
  static String? _nameLengthError(String domain, String local) {
    final String domainLower = domain.toLowerCase();
    final List<int>? window = _nameLengthByDomain[domainLower];
    if (window == null) return null;
    // A provider that ignores dots does not count them towards the name either -
    // Gmail's `a.b.cdef` is a 6-character username, not 8.
    final int length = _dotsInsignificantDomains.contains(domainLower)
        ? _gmailUsername(local).length
        : local.length;
    if (length >= window[0] && length <= window[1]) return null;
    return localLengthMessage(domainLower, window[0], window[1]);
  }

  // ==========================================================================
  // Mailbox identity (Auth - ChinShunYon)
  //
  // One mailbox = one account. Providers that deliver a salted spelling to the
  // SAME mailbox as its base form are rewritten to that base form before the
  // address is ever handed to Supabase, so every variant signs the tourist into
  // one Supabase user - and therefore one `tourist` row.
  //
  // ONLY verified providers are listed. Anything unknown - every custom domain
  // included - is left exactly as typed, so a gap in this table costs coverage
  // (someone can still salt from that provider) and never blocks a legitimate
  // address.
  // ==========================================================================

  /// Providers whose local part is delivered with dots ignored, so
  /// `a.b@…` and `ab@…` are one and the same mailbox.
  ///
  /// Verified: gmail.com / googlemail.com (documented Google behaviour).
  /// Adding `yandex.*` would need a source - do not guess here.
  static const Set<String> _dotsInsignificantDomains = <String>{
    'gmail.com',
    'googlemail.com',
  };

  /// Providers that deliver `base+tag@domain` into `base@domain`.
  ///
  /// Scope matches [_localSpecialsByDomain]: the globally dominant consumer
  /// providers and their domains. Yahoo and Proton are included on the strength
  /// of the `+` convention (RFC 5233 / Sieve subaddressing), which they follow
  /// alongside Gmail, Microsoft and Apple.
  ///
  /// Merging is safe for any provider whose usernames cannot contain `+`: then
  /// a `+` can only ever be an alias suffix, so the worst a wrong entry can do
  /// is point an undeliverable address at the real mailbox the tourist owns.
  /// The merge that WOULD hurt - two real people colliding - needs a provider
  /// that issues usernames containing a literal `+`, and none here do.
  static const Set<String> _subaddressDomains = <String>{
    'gmail.com',
    'googlemail.com',
    'outlook.com',
    'hotmail.com',
    'live.com',
    'msn.com',
    'icloud.com',
    'me.com',
    'mac.com',
    'protonmail.com',
    'proton.me',
    'yahoo.com',
    'ymail.com',
  };

  /// Domains a provider permanently binds to ONE mailbox.
  ///
  /// Verified: Google serves googlemail.com and gmail.com from the same
  /// account.
  ///
  /// Deliberately NOT listed: the Microsoft domains (outlook.com / hotmail.com
  /// / live.com / msn.com) and Apple's (icloud.com / me.com / mac.com).
  /// Microsoft lets a user *alias* its domains by hand and Apple does the same
  /// for legacy Apple IDs, but neither is automatic - merging them would be a
  /// guess, and a wrong guess merges two real people.
  static const Map<String, String> _boundDomainAliases = <String, String>{
    'googlemail.com': 'gmail.com',
  };

  /// The mailbox identity of [email] - the single form every salted spelling of
  /// one mailbox collapses to.
  ///
  /// Also the key for the 3-per-10 send gate: dot and `+tag` variants share one
  /// quota instead of each getting a fresh bucket, which is what made the old
  /// per-string counter trivially bypassable.
  ///
  /// Pure and total: an address it cannot parse is returned trimmed and
  /// lowercased, unchanged otherwise.
  String canonicalEmail(String email) {
    final String trimmed = email.trim().toLowerCase();
    final int at = trimmed.lastIndexOf('@');
    if (at <= 0) return trimmed;

    final String rawDomain = trimmed.substring(at + 1);
    final String domain = _boundDomainAliases[rawDomain] ?? rawDomain;
    String local = trimmed.substring(0, at);

    if (_dotsInsignificantDomains.contains(domain)) {
      local = local.replaceAll('.', '');
    }
    if (_subaddressDomains.contains(domain)) {
      final int plus = local.indexOf('+');
      if (plus > 0) local = local.substring(0, plus);
    }
    // Safety rail: never emit an address with nothing before the "@". (The
    // format guard already prevents this - a dot cannot lead, and a "+" cannot
    // be the first character - but the rewrite must not be able to produce an
    // unsendable address even if those rules change.)
    if (local.isEmpty) return trimmed;
    return '$local@$domain';
  }

  /// True when [email] is a salted spelling of a mailbox rather than the form
  /// the code is actually sent to. The OTP screen mentions the rewrite when it
  /// is, so "sent to" never looks like a different address than the one typed.
  bool isSaltedEmail(String email) {
    final String typed = email.trim().toLowerCase();
    return typed.isNotEmpty && canonicalEmail(email) != typed;
  }

  /// True when [value] holds only printable ASCII - `!` (0x21) to `~` (0x7E).
  static bool _isPrintableAscii(String value) {
    for (final int unit in value.codeUnits) {
      if (unit < 0x21 || unit > 0x7E) return false;
    }
    return true;
  }

  /// The Gmail username behind [local] - dots and a `+tag` suffix removed.
  static String _gmailUsername(String local) {
    final int plus = local.indexOf('+');
    final String withoutTag = plus > 0 ? local.substring(0, plus) : local;
    return withoutTag.replaceAll('.', '');
  }

  /// Why [value] is not a deliverable email address, or null when it is one.
  ///
  /// Pure - no repository, no network. Used by the login screen to block the
  /// Send-OTP button and by [sendEmailOtp]/[verifyEmailOtp] as a final guard.
  ///
  /// One house rule for every domain: letters, digits, dot separators and
  /// [_defaultLocalSpecials]. Deliberately stricter than RFC 5322, which also
  /// permits `o'brien@…`, `first!last@…` and the rest of `atext` - legal, but
  /// issued by no consumer provider and extra escaping for every tool that
  /// later touches the address.
  ///
  /// A VERIFIED provider narrows it further (see [_localSpecialsByDomain]).
  ///
  /// It also rejects what a tourist would actually mistype:
  ///   * boundary failures - `username@`, `@domain.com`, `username@domain`
  ///     (no dot, so no TLD), `username@domain.c` (one-letter TLD);
  ///   * a name that starts or ends with a symbol - `+tag@…`, `user+@…`;
  ///   * dot errors - `.user@…`, `user.@…`, `user..name@…`, `…@domain.`;
  ///   * formatting blunders - spaces, more than one `@`, or characters
  ///     outside the allowed set;
  ///   * salting - a dot in a Gmail name, or a `+tag` on a provider that
  ///     subaddresses ([aliasNotAllowedMessage], [dotsIgnoredMessage]).
  ///
  /// `null` when [value] is empty/whitespace - an empty field is "required",
  /// a separate concern from "malformed" (the caller decides which message to
  /// show for an untouched field).
  String? emailError(String value) {
    final String email = value.trim();
    if (email.isEmpty) return null;
    if (email.length > 254) return emailTooLongMessage;
    if (email.contains(RegExp(r'\s'))) return emailSpaceMessage;

    // ASCII only: the app does not support internationalized (SMTPUTF8)
    // addresses yet, and this is also what rejects the invisible characters
    // (zero-width joiners, bidi overrides) that let one address impersonate
    // another. A space is ASCII, so its specific message above still wins.
    if (!_isPrintableAscii(email)) return emailNonAsciiMessage;

    // Exactly one '@', with a local part before it and a domain after it.
    final int firstAt = email.indexOf('@');
    final int lastAt = email.lastIndexOf('@');
    if (firstAt < 0) return emailMissingAtMessage;
    if (firstAt != lastAt) return emailTooManyAtMessage;
    if (firstAt == 0) return emailMissingNameMessage;
    if (firstAt == email.length - 1) return emailMissingDomainMessage;

    final String local = email.substring(0, firstAt);
    final String domain = email.substring(firstAt + 1);

    // Local part: letters, digits and the dot separators, plus the symbols the
    // domain allows. Dots may not lead, trail or double; a name never starts or
    // ends with a symbol; and a verified provider may allow fewer symbols than
    // our default set does.
    if (local.length > 64 || domain.length > 253) return emailTooLongMessage;
    if (local.contains('..') || local.startsWith('.') || local.endsWith('.')) {
      return emailDotMessage;
    }
    final String? providerSpecials =
        _localSpecialsByDomain[domain.toLowerCase()];
    final String allowedSpecials = providerSpecials ?? _defaultLocalSpecials;
    for (final String char in local.split('')) {
      if (_isAsciiLetterOrDigit(char) || char == '.') continue;
      if (allowedSpecials.contains(char)) continue;
      // A verified provider's rule is a fact about that provider, so the message
      // can name it. Our own default is a house rule and stays generic - we
      // cannot claim what an unlisted domain forbids.
      return providerSpecials == null
          ? emailInvalidCharMessage
          : localCharNotAllowedMessage(domain.toLowerCase(), char);
    }
    if (!_isAsciiLetterOrDigit(local[0]) ||
        !_isAsciiLetterOrDigit(local[local.length - 1])) {
      return emailLocalEdgeMessage;
    }
    // A provider that insists on a letter start (Yahoo). Runs after the edge
    // rule, which has already refused a leading symbol - this catches the digit
    // that rule allows.
    final String domainLower = domain.toLowerCase();
    if (_letterStartDomains.contains(domainLower) &&
        !_isAsciiLetter(local[0])) {
      return localLetterStartMessage(domainLower);
    }
    // A provider that refuses two symbols in a row (Proton). Runs after the
    // character and edge rules so a disallowed symbol still reports as itself.
    if (_noConsecutiveSpecialsDomains.contains(domainLower) &&
        _hasConsecutiveSpecials(local)) {
      return consecutiveSpecialsMessage(domainLower);
    }

    // Domain: at least one dot (a real TLD), letter/digit/hyphen labels, no
    // leading/trailing/doubled dots, and a TLD of two or more letters.
    if (domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.contains('..')) {
      return emailDotMessage;
    }
    if (!domain.contains('.')) return emailNoTldMessage;
    final List<String> labels = domain.split('.');
    final String tld = labels.last;
    if (tld.length < 2 || !RegExp(r'^[A-Za-z]{2,}$').hasMatch(tld)) {
      return emailTldBadMessage;
    }
    for (final String label in labels) {
      if (label.isEmpty) return emailDotMessage;
      if (!RegExp(
        r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
      ).hasMatch(label)) {
        return emailInvalidDomainMessage;
      }
    }

    // Name length, only after the shape is known good: Gmail issues 6-30
    // (dots and the `+tag` suffix not counted) and iCloud 3-20. A domain with no
    // verified window is not checked here - a custom domain keeps whatever
    // length its admin chose.
    final String? lengthError = _nameLengthError(domain, local);
    if (lengthError != null) return lengthError;

    // Salting, blocked at the field (Auth - ChinShunYon). A dot in a Gmail name,
    // or a `+tag` on a provider that subaddresses, names the SAME mailbox - so
    // it could never buy a second account, and letting it through would store an
    // address the tourist never typed. Last, so a genuinely malformed address
    // still gets the shape message above instead of a suggestion that would also
    // be invalid.
    if (_subaddressDomains.contains(domainLower) && local.contains('+')) {
      return aliasNotAllowedMessage(canonicalEmail(email));
    }
    if (_dotsInsignificantDomains.contains(domainLower) &&
        local.contains('.')) {
      return dotsIgnoredMessage(canonicalEmail(email));
    }

    return null;
  }

  /// Sends a passwordless OTP to [email], gated by the per-email rate limit.
  ///
  /// Only a *successful* send is recorded, so a mistyped / rejected address
  /// never burns one of the three slots.
  Future<void> sendEmailOtp(String email) async {
    final String normalizedEmail = email.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    // Defense in depth: the login screen blocks malformed addresses before
    // navigation, but the OTP screen can also be reached with a stale pending
    // email (deep-link/restart). Never ask Supabase to mail a string that
    // cannot be an address.
    final String? formatError = emailError(normalizedEmail);
    if (formatError != null) {
      throw ArgumentError(formatError);
    }

    // Mailbox identity (Auth - ChinShunYon): everything below works on the
    // canonical form, so every salted spelling of one mailbox shares a single
    // quota AND lands on a single Supabase user - one mailbox, one account.
    final String identity = canonicalEmail(normalizedEmail);

    await _assertWithinOtpSendLimit(identity);
    await repository.sendEmailOtp(identity);
    await repository.recordOtpSend(identity);
  }

  /// The full send gate, most immediate rule first: the device-wide cooldown,
  /// then the per-address 3-per-10 cap.
  Future<void> _assertWithinOtpSendLimit(String identity) async {
    _assertDeviceCooldown();
    final List<DateTime> sends = await repository.otpSendTimes(identity);
    final DateTime cutoff = DateTime.now().subtract(otpSendRateWindow);
    final int recent = sends.where((DateTime t) => t.isAfter(cutoff)).length;
    if (recent >= otpSendRateLimit) {
      throw StateError(otpSendRateLimitMessage);
    }
  }

  /// Blocks a send while this device is still inside [otpDeviceCooldown] of its
  /// previous one, whichever address that was for.
  void _assertDeviceCooldown() {
    final DateTime? last = repository.otpLastDeviceSendAt;
    if (last == null) return;
    if (DateTime.now().difference(last) < otpDeviceCooldown) {
      throw StateError(otpDeviceCooldownMessage);
    }
  }

  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final String normalizedEmail = email.trim();
    final String normalizedToken = token.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    // Same final guard as [sendEmailOtp]: never hand a malformed address to
    // the verification call.
    final String? formatError = emailError(normalizedEmail);
    if (formatError != null) {
      throw ArgumentError(formatError);
    }

    if (normalizedToken.isEmpty) {
      throw ArgumentError('OTP cannot be empty.');
    }

    final AuthSession? session = await repository.verifyEmailOtp(
      // Same rewrite as [sendEmailOtp] (Auth - ChinShunYon): the address has to
      // be spelled exactly like the one the code was sent to, so both paths
      // must canonicalise identically.
      email: canonicalEmail(normalizedEmail),
      token: normalizedToken,
    );

    // The first successful verification is also a registration: provision the
    // tourist row the moment the account is authenticated (the UX has no
    // separate register screen).
    if (session != null) {
      await repository.getOrCreateTourist(session);
    }

    return session;
  }

  /// Completes a Google OAuth sign-in after the user returns from the
  /// browser. Picks up the session Supabase established via the deep link,
  /// then auto-creates the tourist row on first sign-in.
  ///
  /// Returns the tourist, or `null` when the flow did not actually complete
  /// (no session yet - e.g. the user cancelled in the browser).
  Future<Tourist?> completeGoogleSignIn() async {
    final AuthSession? session = await repository.getCurrentSession();
    if (session == null) return null;
    return repository.getOrCreateTourist(session);
  }

  /// Returns the [Tourist] row for [session]'s auth user, auto-creating it on
  /// first sign-in.
  Future<Tourist?> getOrCreateTourist(AuthSession session) =>
      repository.getOrCreateTourist(session);

  String get pendingEmail => repository.pendingAuthEmail;

  /// When the freshest code for the pending email was sent, or null when no
  /// code is pending (see `AuthRepository`'s Option B pending-OTP marker).
  DateTime? get pendingOtpSentAt => repository.pendingOtpSentAt;

  /// Auth -----
  /// When this device last sent ANY code, whichever address it was for, or
  /// null when it has not sent one yet - the anchor of the device-wide
  /// cooldown that [sendEmailOtp] enforces (see [otpDeviceCooldown]).
  DateTime? get otpLastDeviceSendAt => repository.otpLastDeviceSendAt;

  /// Auth end ----

  Future<bool> signInWithGoogle({required String redirectTo}) {
    return repository.signInWithGoogle(redirectTo: redirectTo);
  }

  Future<AuthSession?> getCurrentSession() {
    return repository.getCurrentSession();
  }

  Future<void> signOut() {
    return repository.signOut();
  }

  String get currentUserId => repository.currentUserId;

  Future<String?> currentTouristId() {
    return repository.currentTouristId();
  }
}
