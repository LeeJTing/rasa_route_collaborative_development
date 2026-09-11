import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/repositories/restaurant_repository.dart';

void main() {
  final RestaurantRepository repository = RestaurantRepository();

  test('maps closed, 24-hour and timed normalized rows', () {
    final List<OpeningHour> rows = repository.openingHoursFromRows(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'opening_hours_id': 1,
          'day': 'Monday',
          'status': 'closed',
          'opening_time': null,
          'closing_time': null,
        },
        <String, dynamic>{
          'opening_hours_id': 2,
          'day': 'Tuesday',
          'status': 'open',
          'opening_time': '00:00:00',
          'closing_time': '23:59:59',
        },
        <String, dynamic>{
          'opening_hours_id': 3,
          'day': 'Wednesday',
          'status': 'open',
          'opening_time': '09:00:00',
          'closing_time': '15:00:00',
        },
      ],
    );

    expect(rows[0].status, DayStatus.closed);
    expect(rows[1].opensAt, 0);
    expect(rows[1].closesAt, 1440);
    expect(rows[2].day, Weekday.wednesday);
    expect(rows[2].opensAt, 9 * 60);
    expect(rows[2].closesAt, 15 * 60);
  });

  test('maps overnight ranges from database times', () {
    final List<OpeningHour> rows = repository.openingHoursFromRows(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'opening_hours_id': 4,
          'day': 'Monday',
          'status': 'open',
          'opening_time': '12:15:00',
          'closing_time': '22:00:00',
        },
        <String, dynamic>{
          'opening_hours_id': 5,
          'day': 'Tuesday',
          'status': 'open',
          'opening_time': '17:00:00',
          'closing_time': '00:00:00',
        },
      ],
    );

    expect(rows[0].opensAt, 12 * 60 + 15);
    expect(rows[0].closesAt, 22 * 60);
    expect(rows[1].opensAt, 17 * 60);
    expect(rows[1].closesAt, 0);
  });

  test('preserves unknown and ignores invalid enum values', () {
    final List<OpeningHour> rows = repository.openingHoursFromRows(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'opening_hours_id': 6,
          'day': 'Friday',
          'status': 'unknown',
          'opening_time': null,
          'closing_time': null,
        },
        <String, dynamic>{
          'opening_hours_id': 7,
          'day': 'Funday',
          'status': 'open',
          'opening_time': '09:00:00',
          'closing_time': '17:00:00',
        },
      ],
    );

    expect(rows.single.status, DayStatus.unknown);
  });

  test('accepts imported 24:00 as end-of-day midnight', () {
    final List<OpeningHour> rows = repository.openingHoursFromRows(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'opening_hours_id': 8,
          'day': 'Saturday',
          'status': 'open',
          'opening_time': '00:00:00',
          'closing_time': '24:00:00',
        },
      ],
    );

    expect(rows.single.opensAt, 0);
    expect(rows.single.closesAt, 1440);
  });
}
