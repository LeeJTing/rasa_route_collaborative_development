import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_category.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_claim.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/report_moderation_rules.dart';

/// One degree of latitude is ~111.32 km, so these offsets are metres.
double _northMetres(double metres) => metres / 111320;

void main() {
  group('on-site validity', () {
    const TouristLocation spot = TouristLocation(
      latitude: 3.14,
      longitude: 101.69,
    );

    test('a reporter next to the spot is valid', () {
      expect(
        ReportModerationRules.isWithinOnsiteRange(
          TouristLocation(latitude: 3.14 + _northMetres(40), longitude: 101.69),
          spot,
        ),
        isTrue,
      );
    });

    test('a reporter 60 m away is not', () {
      expect(
        ReportModerationRules.isWithinOnsiteRange(
          TouristLocation(latitude: 3.14 + _northMetres(60), longitude: 101.69),
          spot,
        ),
        isFalse,
      );
    });

    test('no fix on either side is never valid', () {
      expect(
        ReportModerationRules.isWithinOnsiteRange(
          TouristLocation.unknown,
          spot,
        ),
        isFalse,
      );
      expect(
        ReportModerationRules.isWithinOnsiteRange(
          spot,
          TouristLocation.unknown,
        ),
        isFalse,
      );
    });
  });

  group('pin consensus', () {
    TouristLocation pin(double northMetres) => TouristLocation(
      latitude: 3.14 + _northMetres(northMetres),
      longitude: 101.69,
    );

    test('three agreeing pins give the median of those three', () {
      final TouristLocation? agreed = ReportModerationRules.consensusLocation(
        <TouristLocation>[pin(0), pin(10), pin(20)],
      );

      expect(agreed, isNotNull);
      expect(agreed!.latitude, closeTo(3.14 + _northMetres(10), 1e-9));
      expect(agreed.longitude, closeTo(101.69, 1e-9));
    });

    test('two agreeing pins are not a consensus', () {
      expect(
        ReportModerationRules.consensusLocation(<TouristLocation>[
          pin(0),
          pin(5),
          pin(400),
        ]),
        isNull,
      );
    });

    test('dissenters are left out of the applied spot', () {
      final TouristLocation? agreed = ReportModerationRules.consensusLocation(
        <TouristLocation>[pin(0), pin(10), pin(20), pin(500)],
      );

      expect(agreed, isNotNull);
      // The median of the three who agree - not of all four.
      expect(agreed!.latitude, closeTo(3.14 + _northMetres(10), 1e-9));
    });

    test('below three pins there is nothing to agree on', () {
      expect(
        ReportModerationRules.consensusLocation(<TouristLocation>[
          pin(0),
          pin(5),
        ]),
        isNull,
      );
      expect(
        ReportModerationRules.consensusLocation(const <TouristLocation>[]),
        isNull,
      );
    });
  });

  group('thresholds', () {
    test('each category has the approved threshold', () {
      expect(
        ReportModerationRules.thresholdFor(ReportCategory.operatingHours),
        10,
      );
      expect(ReportModerationRules.thresholdFor(ReportCategory.itemPrice), 5);
      expect(
        ReportModerationRules.thresholdFor(ReportCategory.itemNotExist),
        5,
      );
      expect(ReportModerationRules.thresholdFor(ReportCategory.address), 5);
      expect(
        ReportModerationRules.thresholdFor(ReportCategory.closedPermanently),
        10,
      );
      expect(
        ReportModerationRules.thresholdFor(ReportCategory.closedTemporarily),
        10,
      );
    });

    test('reachesThreshold is inclusive at the boundary', () {
      expect(
        ReportModerationRules.reachesThreshold(ReportCategory.itemPrice, 5),
        isTrue,
      );
      expect(
        ReportModerationRules.reachesThreshold(
          ReportCategory.operatingHours,
          9,
        ),
        isFalse,
      );
    });
  });

  group('claim expiry (a report expires after one year)', () {
    final DateTime now = DateTime.utc(2026, 9, 14);

    test('the lifetime is one year', () {
      expect(reportClaimLifetime, const Duration(days: 365));
      expect(ReportModerationRules.claimLifetime, reportClaimLifetime);
    });

    test('a claim younger than a year still counts', () {
      expect(
        ReportModerationRules.isClaimExpired(
          now.subtract(const Duration(days: 364)),
          now,
        ),
        isFalse,
      );
    });

    test('exactly a year is still alive; one day more is expired', () {
      expect(
        ReportModerationRules.isClaimExpired(
          now.subtract(const Duration(days: 365)),
          now,
        ),
        isFalse,
      );
      expect(
        ReportModerationRules.isClaimExpired(
          now.subtract(const Duration(days: 366)),
          now,
        ),
        isTrue,
      );
    });

    test('an unreadable timestamp is never expired', () {
      expect(ReportModerationRules.isClaimExpired(null, now), isFalse);
    });
  });

  group('hours payload', () {
    test('serialises a single Open range canonically', () {
      expect(
        ReportModerationRules.hoursPayload(<ProposedDayHours>[
          ProposedDayHours(status: DayStatus.open, opensAt: 540, closesAt: 900),
        ]),
        'hours:open:540:900',
      );
    });

    test('Closed rows carry no times', () {
      expect(
        ReportModerationRules.hoursPayload(<ProposedDayHours>[
          ProposedDayHours(status: DayStatus.closed),
        ]),
        'hours:closed',
      );
    });

    test('multiple ranges sort so order never changes identity', () {
      final String
      first = ReportModerationRules.hoursPayload(<ProposedDayHours>[
        ProposedDayHours(status: DayStatus.open, opensAt: 780, closesAt: 1020),
        ProposedDayHours(status: DayStatus.open, opensAt: 480, closesAt: 660),
      ]);
      final String
      second = ReportModerationRules.hoursPayload(<ProposedDayHours>[
        ProposedDayHours(status: DayStatus.open, opensAt: 480, closesAt: 660),
        ProposedDayHours(status: DayStatus.open, opensAt: 780, closesAt: 1020),
      ]);
      expect(first, second);
    });

    test('parseHoursPayload round-trips', () {
      final String payload = ReportModerationRules.hoursPayload(
        <ProposedDayHours>[
          ProposedDayHours(status: DayStatus.open, opensAt: 540, closesAt: 900),
          ProposedDayHours(status: DayStatus.closed),
        ],
      );
      final List<ProposedDayHours> parsed =
          ReportModerationRules.parseHoursPayload(payload);
      expect(parsed, hasLength(2));
      final Map<DayStatus, ProposedDayHours> byStatus =
          <DayStatus, ProposedDayHours>{
            for (final ProposedDayHours day in parsed) day.status: day,
          };
      expect(byStatus[DayStatus.open]!.opensAt, 540);
      expect(byStatus[DayStatus.open]!.closesAt, 900);
      expect(byStatus.containsKey(DayStatus.closed), isTrue);
    });

    test('parseHoursPayload rejects malformed strings', () {
      expect(
        ReportModerationRules.parseHoursPayload('address:12 Main St'),
        isEmpty,
      );
      expect(
        ReportModerationRules.parseHoursPayload('hours:open:not-a-number:5'),
        isEmpty,
      );
    });
  });

  group('item / address payloads', () {
    test('price is formatted with a fixed scale so 8.5 == 8.50', () {
      expect(ReportModerationRules.pricePayload(8.5), 'price:8.50');
      expect(ReportModerationRules.pricePayload(8.50), 'price:8.50');
      expect(
        ReportModerationRules.pricePayload(8.5),
        ReportModerationRules.pricePayload(8.50),
      );
    });

    test('item-not-exist and closed-permanently are constants', () {
      expect(ReportModerationRules.itemNotExistPayload, 'not-exist');
      expect(
        ReportModerationRules.closedPermanentlyPayload,
        'closed-permanently',
      );
    });

    test('address trims surrounding whitespace', () {
      expect(
        ReportModerationRules.addressPayload('  12 Jalan Merdeka  '),
        'address:12 Jalan Merdeka',
      );
    });
  });

  group('temporary closure payload', () {
    test('serialises days and months', () {
      expect(
        ReportModerationRules.temporaryClosurePayload(
          const ProposedClosure(amount: 3, unit: ClosureUnit.days),
        ),
        'closed-temporarily:3:days',
      );
      expect(
        ReportModerationRules.temporaryClosurePayload(
          const ProposedClosure(amount: 2, unit: ClosureUnit.months),
        ),
        'closed-temporarily:2:months',
      );
    });

    test('parseTemporaryClosurePayload round-trips and rejects garbage', () {
      const ProposedClosure closure = ProposedClosure(
        amount: 5,
        unit: ClosureUnit.days,
      );
      final String payload = ReportModerationRules.temporaryClosurePayload(
        closure,
      );
      final ProposedClosure? parsed =
          ReportModerationRules.parseTemporaryClosurePayload(payload);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 5);
      expect(parsed.unit, ClosureUnit.days);

      expect(
        ReportModerationRules.parseTemporaryClosurePayload(
          'closed-temporarily:0:days',
        ),
        isNull,
      );
      expect(
        ReportModerationRules.parseTemporaryClosurePayload('price:5.00'),
        isNull,
      );
    });

    test('closureDurationDays uses 30-day months', () {
      expect(
        ReportModerationRules.closureDurationDays(
          const ProposedClosure(amount: 4, unit: ClosureUnit.days),
        ),
        4,
      );
      expect(
        ReportModerationRules.closureDurationDays(
          const ProposedClosure(amount: 2, unit: ClosureUnit.months),
        ),
        60,
      );
    });
  });

  group('report input validation', () {
    test('price accepts a realistic amount and rejects unsafe values', () {
      expect(ReportModerationRules.priceError('8.50', required: true), isNull);
      expect(ReportModerationRules.priceError('', required: true), isNotNull);
      expect(ReportModerationRules.priceError('0', required: true), isNotNull);
      // The cap matches the Add-Landmark form (2026-09-13): 9999.99 max.
      expect(
        ReportModerationRules.priceError('1000.01', required: true),
        isNull,
      );
      expect(
        ReportModerationRules.priceError('9999.99', required: true),
        isNull,
      );
      expect(
        ReportModerationRules.priceError('10000', required: true),
        isNotNull,
      );
    });

    test("address is judged by the Add-Landmark form's own rules", () {
      expect(
        ReportModerationRules.addressError(
          '12 Jalan Merdeka, Kuala Lumpur',
          required: true,
        ),
        isNull,
      );
      expect(
        ReportModerationRules.addressError('', required: true),
        'Enter the corrected address.',
      );
      expect(
        ReportModerationRules.addressError('---', required: true),
        'Invalid address.',
      );
      // No digit - the form rejects this too (a Malaysian address carries a
      // house/unit/lot number).
      expect(
        ReportModerationRules.addressError('Jalan Ampang', required: true),
        'Invalid address.',
      );
      // Shorter than the form's minimum.
      expect(
        ReportModerationRules.addressError('12 A', required: true),
        'Invalid address.',
      );
      // Characters the form does not allow in an address.
      expect(
        ReportModerationRules.addressError(
          "12, Jalan O'Brien, KL",
          required: true,
        ),
        'Invalid address.',
      );
      // The 150 cap is the form's hard stop: typing is capped there, so 150
      // itself is "too long" and 149 is the last acceptable length.
      expect(
        ReportModerationRules.addressError(
          '12, Jalan A'.padRight(149, 'A'), // 149 characters
          required: true,
        ),
        isNull,
      );
      expect(
        ReportModerationRules.addressError(
          '12, Jalan A'.padRight(150, 'A'), // 150 characters
          required: true,
        ),
        'Address is too long.',
      );
      // Shape is judged BEFORE the cap, exactly like the form: a long value
      // with no house number is "Invalid address.", not "too long".
      expect(
        ReportModerationRules.addressError(
          'A'.padRight(200, 'A'),
          required: true,
        ),
        'Invalid address.',
      );
      // Control characters are judged on the RAW text, exactly like the form
      // (a trailing newline is not trimmed away first).
      expect(
        ReportModerationRules.addressError(
          '12, Jalan Merdeka, Kuala Lumpur\n',
          required: true,
        ),
        'Invalid address.',
      );
      // Whitespace alone is an empty answer on a required field.
      expect(
        ReportModerationRules.addressError('   ', required: true),
        'Enter the corrected address.',
      );
      // Optional field: empty is not an error until it is submitted.
      expect(ReportModerationRules.addressError(''), isNull);
    });

    test('temporary closure respects the selected unit limit', () {
      expect(
        ReportModerationRules.closureError(
          '12',
          ClosureUnit.months,
          required: true,
        ),
        isNull,
      );
      expect(
        ReportModerationRules.closureError(
          '13',
          ClosureUnit.months,
          required: true,
        ),
        isNotNull,
      );
    });

    test('opening hours reject incomplete and overlapping ranges', () {
      expect(
        ReportModerationRules.operatingHoursError(<Weekday, List<OpeningHour>>{
          Weekday.monday: const <OpeningHour>[
            OpeningHour(id: 0, day: Weekday.monday, status: DayStatus.open),
          ],
        }),
        isNotNull,
      );
      expect(
        ReportModerationRules.operatingHoursError(<Weekday, List<OpeningHour>>{
          Weekday.monday: const <OpeningHour>[
            OpeningHour(
              id: 0,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 540,
              closesAt: 720,
            ),
            OpeningHour(
              id: 0,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 660,
              closesAt: 780,
            ),
          ],
        }),
        isNotNull,
      );
    });
  });

  group('resolveClosureUntil (the agreed END DATE)', () {
    // 09:00 Malaysia time, so date maths is easy to reason about.
    final DateTime now = DateTime.utc(2026, 9, 14, 1);

    ClosureClaim claim(
      DateTime at,
      int amount, [
      ClosureUnit unit = ClosureUnit.days,
    ]) => ClosureClaim(
      payload: ReportModerationRules.temporaryClosurePayload(
        ProposedClosure(amount: amount, unit: unit),
      ),
      createdAt: at,
    );

    test('staggered reports meaning the same end date vote together', () {
      // The user's example: 15/14/13/13/12-day claims filed 3/2/1/1/0 days
      // ago - all 10 point at the SAME day (today + 12).
      final DateTime? agreed =
          ReportModerationRules.resolveClosureUntil(<ClosureClaim>[
            claim(now.subtract(const Duration(days: 3)), 15),
            claim(now.subtract(const Duration(days: 2)), 14),
            claim(now.subtract(const Duration(days: 1)), 13),
            claim(now.subtract(const Duration(days: 1)), 13),
            for (int i = 0; i < 6; i++) claim(now, 12),
          ]);

      expect(agreed, isNotNull);
      expect(agreed!.difference(now).inDays, 12);
    });

    test('the most-voted end date wins even when older claims dominate', () {
      // 6 claims say 15 days three days ago (end = today+12); 4 say 10 days
      // today (end = today+10). Votes decide, not the raw day-count.
      final DateTime? agreed =
          ReportModerationRules.resolveClosureUntil(<ClosureClaim>[
            for (int i = 0; i < 6; i++)
              claim(now.subtract(const Duration(days: 3)), 15),
            for (int i = 0; i < 4; i++) claim(now, 10),
          ]);

      expect(agreed!.difference(now).inDays, 12);
    });

    test('ties between end dates go to the LATER date', () {
      final DateTime? agreed = ReportModerationRules.resolveClosureUntil(
        <ClosureClaim>[
          for (int i = 0; i < 5; i++) claim(now, 2),
          for (int i = 0; i < 5; i++) claim(now, 9),
        ],
      );

      expect(agreed!.difference(now).inDays, 9);
    });

    test('equivalent durations in different units vote together', () {
      final DateTime? agreed =
          ReportModerationRules.resolveClosureUntil(<ClosureClaim>[
            for (int i = 0; i < 7; i++) claim(now, 30),
            for (int i = 0; i < 5; i++) claim(now, 1, ClosureUnit.months),
            for (int i = 0; i < 5; i++) claim(now, 60),
          ]);

      // 30 days + 1 month (30 days) = 12 votes on the same day.
      expect(agreed!.difference(now).inDays, 30);
    });

    test('a winning date already in the past is returned as-is', () {
      final DateTime? agreed = ReportModerationRules.resolveClosureUntil(
        <ClosureClaim>[claim(now.subtract(const Duration(days: 10)), 5)],
      );

      expect(agreed, now.subtract(const Duration(days: 5)));
    });

    test('ignores non-closure payloads and empty input', () {
      expect(
        ReportModerationRules.resolveClosureUntil(const <ClosureClaim>[]),
        isNull,
      );
      expect(
        ReportModerationRules.resolveClosureUntil(<ClosureClaim>[
          ClosureClaim(payload: 'price:5.00', createdAt: now),
        ]),
        isNull,
      );
    });
  });

  group('issueSignature', () {
    ReportClaim claim({
      ReportPlaceKind kind = ReportPlaceKind.restaurant,
      int placeId = 1,
      ReportCategory category = ReportCategory.itemPrice,
      ReportItemKind? itemKind = ReportItemKind.restaurantItem,
      int? itemId = 42,
      Weekday? day,
      String payload = 'x',
    }) => ReportClaim(
      placeKind: kind,
      placeId: placeId,
      category: category,
      itemKind: itemKind,
      itemId: itemId,
      day: day,
      payload: payload,
    );

    test('ignores the payload (identical claim grouping)', () {
      expect(
        ReportModerationRules.issueSignature(claim(payload: 'price:5.00')),
        ReportModerationRules.issueSignature(claim(payload: 'price:9.00')),
      );
    });

    test('distinguishes place, item and day', () {
      final String base = ReportModerationRules.issueSignature(claim());
      expect(
        ReportModerationRules.issueSignature(claim(placeId: 2)),
        isNot(base),
      );
      expect(
        ReportModerationRules.issueSignature(claim(itemId: 99)),
        isNot(base),
      );
      expect(
        ReportModerationRules.issueSignature(claim(day: Weekday.monday)),
        isNot(base),
      );
    });
  });

  group('operating hours - overnight (same rules as the landmark form)', () {
    test('an encoded overnight row is valid', () {
      expect(
        ReportModerationRules.operatingHoursError(<Weekday, List<OpeningHour>>{
          Weekday.monday: const <OpeningHour>[
            OpeningHour(
              id: 0,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 22 * 60,
              closesAt: 26 * 60, // 02:00 next day
            ),
          ],
        }),
        isNull,
      );
    });

    test('an overnight tail overlapping the next day is rejected', () {
      final String? error = ReportModerationRules.operatingHoursError(
        <Weekday, List<OpeningHour>>{
          Weekday.monday: const <OpeningHour>[
            OpeningHour(
              id: 0,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 22 * 60,
              closesAt: 26 * 60, // 02:00 next day
            ),
          ],
          Weekday.tuesday: const <OpeningHour>[
            OpeningHour(
              id: 0,
              day: Weekday.tuesday,
              status: DayStatus.open,
              opensAt: 60, // 01:00 - inside Monday's tail
              closesAt: 6 * 60,
            ),
          ],
        },
      );
      expect(error, isNotNull);
      expect(error, contains("Monday's overnight hours run until 02:00"));
      expect(error, contains('Tuesday'));
    });
  });
}
