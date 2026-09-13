import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_category.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_claim.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/report_moderation_rules.dart';

void main() {
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

    test('address must contain meaningful text within the length limit', () {
      expect(
        ReportModerationRules.addressError(
          '12 Jalan Merdeka, Kuala Lumpur',
          required: true,
        ),
        isNull,
      );
      expect(ReportModerationRules.addressError('', required: true), isNotNull);
      expect(
        ReportModerationRules.addressError('---', required: true),
        isNotNull,
      );
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

  group('resolveMostCommonClosure', () {
    test('returns the most common duration', () {
      final ProposedClosure? resolved =
          ReportModerationRules.resolveMostCommonClosure(<String>[
            ReportModerationRules.temporaryClosurePayload(
              const ProposedClosure(amount: 3, unit: ClosureUnit.days),
            ),
            ReportModerationRules.temporaryClosurePayload(
              const ProposedClosure(amount: 7, unit: ClosureUnit.days),
            ),
            ReportModerationRules.temporaryClosurePayload(
              const ProposedClosure(amount: 7, unit: ClosureUnit.days),
            ),
            ReportModerationRules.temporaryClosurePayload(
              const ProposedClosure(amount: 7, unit: ClosureUnit.days),
            ),
          ]);
      expect(resolved!.amount, 7);
      expect(resolved.unit, ClosureUnit.days);
    });

    test(
      'ties break to the LONGER duration so the place is never re-opened early',
      () {
        final ProposedClosure? resolved =
            ReportModerationRules.resolveMostCommonClosure(<String>[
              ReportModerationRules.temporaryClosurePayload(
                const ProposedClosure(amount: 2, unit: ClosureUnit.days),
              ),
              ReportModerationRules.temporaryClosurePayload(
                const ProposedClosure(amount: 2, unit: ClosureUnit.days),
              ),
              ReportModerationRules.temporaryClosurePayload(
                const ProposedClosure(amount: 9, unit: ClosureUnit.days),
              ),
              ReportModerationRules.temporaryClosurePayload(
                const ProposedClosure(amount: 9, unit: ClosureUnit.days),
              ),
            ]);
        expect(resolved!.amount, 9);
      },
    );

    test('ignores non-closure payloads and empty input', () {
      expect(
        ReportModerationRules.resolveMostCommonClosure(const <String>[]),
        isNull,
      );
      expect(
        ReportModerationRules.resolveMostCommonClosure(<String>['price:5.00']),
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
