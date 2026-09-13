import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/opening_hours_table.dart';

void main() {
  testWidgets('shows one weekday label for multiple opening ranges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpeningHoursTable(
            openingHours: <OpeningHour>[
              OpeningHour(
                id: 1,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 630,
                closesAt: 900,
              ),
              OpeningHour(
                id: 2,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 1020,
                closesAt: 1320,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('10:30 AM - 3:00 PM'), findsOneWidget);
    expect(find.text('5:00 PM - 10:00 PM'), findsOneWidget);
  });

  testWidgets('shows normalized overnight ranges on their respective days', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpeningHoursTable(
            openingHours: <OpeningHour>[
              OpeningHour(
                id: 1,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 1320,
                closesAt: 1440,
              ),
              OpeningHour(
                id: 2,
                day: Weekday.tuesday,
                status: DayStatus.open,
                opensAt: 0,
                closesAt: 120,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('10:00 PM - 12:00 AM'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('12:00 AM - 2:00 AM'), findsOneWidget);
  });

  testWidgets('an overnight row shows the next-day time with no ("+1") mark', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpeningHoursTable(
            openingHours: <OpeningHour>[
              OpeningHour(
                id: 1,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 600, // 10:00
                closesAt: 1560, // 02:00 the NEXT day (encoded)
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('10:00 AM - 2:00 AM'), findsOneWidget);
    expect(find.textContaining('(+1)'), findsNothing);
    expect(find.textContaining('next day'), findsNothing);
  });

  testWidgets('labels a full-day range as open 24 hours', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpeningHoursTable(
            openingHours: <OpeningHour>[
              OpeningHour(
                id: 1,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 0,
                closesAt: 1440,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Open 24 hours'), findsOneWidget);
  });

  testWidgets('days render Monday-to-Sunday regardless of input order', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpeningHoursTable(
            openingHours: <OpeningHour>[
              OpeningHour(
                id: 3,
                day: Weekday.friday,
                status: DayStatus.open,
                opensAt: 540,
                closesAt: 900,
              ),
              OpeningHour(
                id: 2,
                day: Weekday.wednesday,
                status: DayStatus.open,
                opensAt: 540,
                closesAt: 900,
              ),
              OpeningHour(
                id: 1,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 540,
                closesAt: 900,
              ),
            ],
          ),
        ),
      ),
    );

    final double monday = tester.getTopLeft(find.text('Monday')).dy;
    final double wednesday = tester.getTopLeft(find.text('Wednesday')).dy;
    final double friday = tester.getTopLeft(find.text('Friday')).dy;
    expect(monday, lessThan(wednesday));
    expect(wednesday, lessThan(friday));
  });
}
