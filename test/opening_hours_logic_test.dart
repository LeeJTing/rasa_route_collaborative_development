import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/opening_hours_logic.dart';

void main() {
  final DateTime mondayNoon = DateTime(2026, 9, 7, 12);

  test('missing hours remain unknown rather than closed', () {
    expect(
      OpeningHoursLogic.availabilityAt(const <OpeningHour>[], mondayNoon),
      OpeningHoursAvailability.unknown,
    );
  });

  test('an explicit closed day is confidently closed', () {
    expect(
      OpeningHoursLogic.availabilityAt(const <OpeningHour>[
        OpeningHour(id: 1, day: Weekday.monday, status: DayStatus.closed),
      ], mondayNoon),
      OpeningHoursAvailability.closed,
    );
  });

  test('a rest interval between two ranges is closed', () {
    const List<OpeningHour> hours = <OpeningHour>[
      OpeningHour(
        id: 1,
        day: Weekday.monday,
        status: DayStatus.open,
        opensAt: 10 * 60,
        closesAt: 11 * 60,
      ),
      OpeningHour(
        id: 2,
        day: Weekday.monday,
        status: DayStatus.open,
        opensAt: 13 * 60,
        closesAt: 18 * 60,
      ),
    ];
    expect(
      OpeningHoursLogic.availabilityAt(hours, mondayNoon),
      OpeningHoursAvailability.closed,
    );
  });

  test('an overnight range remains open after midnight', () {
    expect(
      OpeningHoursLogic.availabilityAt(const <OpeningHour>[
        OpeningHour(
          id: 1,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 20 * 60,
          closesAt: 2 * 60,
        ),
      ], DateTime(2026, 9, 8, 1)),
      OpeningHoursAvailability.open,
    );
  });

  test('malformed open row remains unknown', () {
    expect(
      OpeningHoursLogic.availabilityAt(const <OpeningHour>[
        OpeningHour(id: 1, day: Weekday.monday, status: DayStatus.open),
      ], mondayNoon),
      OpeningHoursAvailability.unknown,
    );
  });
}
