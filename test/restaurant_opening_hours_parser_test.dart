import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/repositories/restaurant_opening_hours_parser.dart';

void main() {
  const RestaurantOpeningHoursParser parser = RestaurantOpeningHoursParser();

  test('parses closed, 24-hour and holiday-labelled days', () {
    final List<OpeningHour> rows = parser.parse(
      '{"Monday":"Closed","Tuesday":"Open 24 hours",'
      '"Wednesday (Mawlid)":"9 am–3 pm, Hours might differ"}',
    );

    expect(rows[0].status, DayStatus.closed);
    expect(rows[1].opensAt, 0);
    expect(rows[1].closesAt, 1440);
    expect(rows[2].day, Weekday.wednesday);
    expect(rows[2].opensAt, 9 * 60);
    expect(rows[2].closesAt, 15 * 60);
  });

  test('infers omitted meridiem without creating an 18-hour range', () {
    final List<OpeningHour> rows = parser.parse(
      '{"Monday":"12:15–10 pm","Tuesday":"5 pm–12 am",'
      '"Wednesday":"9–3 pm"}',
    );

    expect(rows[0].opensAt, 12 * 60 + 15);
    expect(rows[0].closesAt, 22 * 60);
    expect(rows[1].opensAt, 17 * 60);
    expect(rows[1].closesAt, 0);
    expect(rows[2].opensAt, 9 * 60);
    expect(rows[2].closesAt, 15 * 60);
  });

  test('returns unknown for an unrecognised day value', () {
    final List<OpeningHour> rows = parser.parse(
      '{"Friday":"Temporarily closed"}',
    );

    expect(rows.single.status, DayStatus.unknown);
  });
}
