import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/repositories/opening_hours_rows.dart';

/// The ONE place the overnight split convention lives (see
/// `OpeningHoursRows`): the app EDITS "Monday 10:00 -> 02:00 next day" as one
/// row (`closesAt: 1560`), the DB stores it SPLIT (`Mon 10:00-24:00` +
/// `Tue 00:00-02:00`), and reads MERGE the tail back into the Monday row.

OpeningHour _row(
  Weekday day,
  int? opensAt,
  int? closesAt, {
  DayStatus status = DayStatus.open,
  int id = 0,
}) => OpeningHour(
  id: id,
  day: day,
  status: status,
  opensAt: opensAt,
  closesAt: closesAt,
);

void main() {
  group('dayAfter / dayBefore', () {
    test('wrap around the week', () {
      expect(OpeningHoursRows.dayAfter(Weekday.monday), Weekday.tuesday);
      expect(OpeningHoursRows.dayAfter(Weekday.sunday), Weekday.monday);
      expect(OpeningHoursRows.dayBefore(Weekday.monday), Weekday.sunday);
      expect(OpeningHoursRows.dayBefore(Weekday.sunday), Weekday.saturday);
    });
  });

  group('splitForStorage', () {
    test('a same-day row is written as itself', () {
      final List<OpeningHour> rows = OpeningHoursRows.splitForStorage(
        _row(Weekday.monday, 600, 840),
      );
      expect(rows, hasLength(1));
      expect(rows.single.day, Weekday.monday);
      expect(rows.single.opensAt, 600);
      expect(rows.single.closesAt, 840);
    });

    test('an overnight row becomes an end-of-day row plus a next-day tail', () {
      final List<OpeningHour> rows = OpeningHoursRows.splitForStorage(
        _row(Weekday.monday, 600, 1560), // 10:00 -> 02:00 next day
      );
      expect(rows, hasLength(2));
      expect(rows[0].day, Weekday.monday);
      expect(rows[0].status, DayStatus.open);
      expect(rows[0].opensAt, 600);
      expect(rows[0].closesAt, 1440); // 24:00
      expect(rows[1].day, Weekday.tuesday);
      expect(rows[1].status, DayStatus.open);
      expect(rows[1].opensAt, 0); // 00:00
      expect(rows[1].closesAt, 120); // 02:00
    });

    test('a midnight close (1440) is NOT split - there is no tail', () {
      expect(
        OpeningHoursRows.splitForStorage(_row(Weekday.monday, 600, 1440)),
        hasLength(1),
      );
    });

    test('a Sunday overnight row wraps its tail onto Monday', () {
      final List<OpeningHour> rows = OpeningHoursRows.splitForStorage(
        _row(Weekday.sunday, 600, 1560),
      );
      expect(rows, hasLength(2));
      expect(rows[1].day, Weekday.monday);
    });

    test('closed rows are written as themselves', () {
      final List<OpeningHour> rows = OpeningHoursRows.splitForStorage(
        _row(Weekday.monday, null, null, status: DayStatus.closed),
      );
      expect(rows, hasLength(1));
      expect(rows.single.status, DayStatus.closed);
    });
  });

  group('isTailCandidate / endsAtEndOfDay', () {
    test('a 00:00 start ending in the small hours is a tail candidate', () {
      expect(
        OpeningHoursRows.isTailCandidate(_row(Weekday.tuesday, 0, 120)),
        isTrue,
      );
    });

    test('an all-day 00:00-23:59:59 row is NOT a tail candidate', () {
      expect(
        OpeningHoursRows.isTailCandidate(_row(Weekday.tuesday, 0, 1439)),
        isFalse,
      );
    });

    test('a 00:00 opening that never closes is not a tail candidate', () {
      expect(
        OpeningHoursRows.isTailCandidate(_row(Weekday.tuesday, 0, 0)),
        isFalse,
      );
    });

    test('endsAtEndOfDay accepts 24:00 and 23:59 but rejects real closes', () {
      expect(
        OpeningHoursRows.endsAtEndOfDay(_row(Weekday.monday, 600, 1440)),
        isTrue,
      );
      expect(
        OpeningHoursRows.endsAtEndOfDay(_row(Weekday.monday, 600, 1439)),
        isTrue,
      );
      expect(
        OpeningHoursRows.endsAtEndOfDay(_row(Weekday.monday, 600, 1380)),
        isFalse,
      );
    });
  });

  group('mergeTails', () {
    test('folds a stored tail back into the previous day', () {
      final List<OpeningHour> merged = OpeningHoursRows.mergeTails(
        <OpeningHour>[
          _row(Weekday.monday, 600, 1440, id: 7),
          _row(Weekday.tuesday, 0, 120, id: 8),
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single.id, 7); // the HOST row keeps its id
      expect(merged.single.day, Weekday.monday);
      expect(merged.single.opensAt, 600);
      expect(merged.single.closesAt, 1560); // 1440 + 120
    });

    test('wraps a Sunday tail onto Monday', () {
      final List<OpeningHour> merged = OpeningHoursRows.mergeTails(
        <OpeningHour>[
          _row(Weekday.monday, 0, 120),
          _row(Weekday.sunday, 600, 1440),
        ],
      );
      final OpeningHour sunday = merged.singleWhere(
        (OpeningHour row) => row.day == Weekday.sunday,
      );
      expect(sunday.closesAt, 1560);
      // Monday's own 00:00-02:00 got merged away.
      expect(merged, hasLength(1));
    });

    test('a 00:00 opening with no previous end-of-day row stays put', () {
      final List<OpeningHour> merged = OpeningHoursRows.mergeTails(
        <OpeningHour>[_row(Weekday.tuesday, 0, 120)],
      );
      expect(merged, hasLength(1));
      expect(merged.single.closesAt, 120);
    });

    test('a tail following a normal same-day close is left alone', () {
      final List<OpeningHour> merged = OpeningHoursRows.mergeTails(
        <OpeningHour>[
          _row(Weekday.monday, 600, 840), // ends 14:00, not midnight
          _row(Weekday.tuesday, 0, 120),
        ],
      );
      expect(merged, hasLength(2));
      expect(
        merged
            .singleWhere((OpeningHour row) => row.day == Weekday.tuesday)
            .closesAt,
        120,
      );
    });

    test('24/7 style all-day rows are never merged', () {
      final List<OpeningHour> merged = OpeningHoursRows.mergeTails(
        <OpeningHour>[
          _row(Weekday.monday, 0, 1439), // 00:00-23:59:59
          _row(Weekday.tuesday, 0, 1439),
          _row(Weekday.wednesday, 0, 1439),
        ],
      );
      expect(merged, hasLength(3));
    });

    test('the merged list is unmodifiable', () {
      final List<OpeningHour> merged = OpeningHoursRows.mergeTails(
        <OpeningHour>[_row(Weekday.monday, 600, 840)],
      );
      expect(
        () => merged.add(_row(Weekday.tuesday, 0, 60)),
        throwsUnsupportedError,
      );
    });
  });

  group('tailOf', () {
    test('returns the next-day tail row of an overnight day', () {
      final Map<Weekday, List<OpeningHour>> merged =
          <Weekday, List<OpeningHour>>{
            Weekday.monday: <OpeningHour>[_row(Weekday.monday, 600, 1560)],
          };
      final OpeningHour? tail = OpeningHoursRows.tailOf(merged, Weekday.monday);
      expect(tail, isNotNull);
      expect(tail!.day, Weekday.tuesday);
      expect(tail.opensAt, 0);
      expect(tail.closesAt, 120);
    });

    test('returns null when the day has no overnight period', () {
      final Map<Weekday, List<OpeningHour>> merged =
          <Weekday, List<OpeningHour>>{
            Weekday.monday: <OpeningHour>[_row(Weekday.monday, 600, 840)],
          };
      expect(OpeningHoursRows.tailOf(merged, Weekday.monday), isNull);
      expect(OpeningHoursRows.tailOf(merged, Weekday.tuesday), isNull);
    });
  });
}
