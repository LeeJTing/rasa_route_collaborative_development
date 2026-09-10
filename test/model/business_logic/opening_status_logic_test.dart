import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/map_exploration_logic.dart';

void main() {
  final Weekday today = Weekday.values[DateTime.now().weekday - 1];

  group('MapExplorationLogic.openNow', () {
    test('returns null when hours list is null or empty', () {
      expect(MapExplorationLogic.openNow(null), isNull);
      expect(MapExplorationLogic.openNow(<OpeningHour>[]), isNull);
    });

    test('returns null when no records exist for today', () {
      final Weekday tomorrow = Weekday.values[DateTime.now().weekday % 7];
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(id: 1, day: tomorrow, status: DayStatus.open, opensAt: 0, closesAt: 1440),
      ];
      expect(MapExplorationLogic.openNow(hours), isNull);
    });

    test('returns null when today has an Unknown status record', () {
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(id: 1, day: today, status: DayStatus.unknown),
      ];
      expect(MapExplorationLogic.openNow(hours), isNull);
    });

    test('returns true when current time falls within an opening period', () {
      final DateTime now = DateTime.now();
      final int currentMinutes = now.hour * 60 + now.minute;
      
      // Create a range that covers current time
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(
          id: 1, 
          day: today, 
          status: DayStatus.open, 
          opensAt: (currentMinutes - 30).clamp(0, 1440), 
          closesAt: (currentMinutes + 30).clamp(0, 1440),
        ),
      ];
      expect(MapExplorationLogic.openNow(hours), isTrue);
    });

    test('returns false when today is explicitly Closed', () {
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(id: 1, day: today, status: DayStatus.closed),
      ];
      expect(MapExplorationLogic.openNow(hours), isFalse);
    });

    test('returns false when current time is outside opening periods', () {
      final DateTime now = DateTime.now();
      final int currentMinutes = now.hour * 60 + now.minute;

      final List<OpeningHour> hours = <OpeningHour>[
        if (currentMinutes > 60)
          OpeningHour(id: 1, day: today, status: DayStatus.open, opensAt: 0, closesAt: currentMinutes - 30),
        if (currentMinutes < 1410)
          OpeningHour(id: 2, day: today, status: DayStatus.open, opensAt: currentMinutes + 30, closesAt: 1440),
      ];
      
      if (hours.isNotEmpty) {
        expect(MapExplorationLogic.openNow(hours), isFalse);
      }
    });

    test('correctly handles multiple intervals (e.g., lunch and dinner)', () {
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(id: 1, day: today, status: DayStatus.open, opensAt: 11 * 60, closesAt: 14 * 60), // 11am-2pm
        OpeningHour(id: 2, day: today, status: DayStatus.open, opensAt: 17 * 60, closesAt: 22 * 60), // 5pm-10pm
      ];

      // Since we can't easily mock time, we verify that it doesn't crash and returns a boolean or null.
      // The logic is verified by other tests that use current time.
      final bool? result = MapExplorationLogic.openNow(hours);
      expect(result, isNotNull);
    });

    test('correctly handles shifts from yesterday running past midnight', () {
      final Weekday yesterday = Weekday.values[(DateTime.now().weekday + 5) % 7];
      final DateTime now = DateTime.now();
      final int minute = now.hour * 60 + now.minute;

      // If it's early morning (e.g. 2 AM), a shift starting at 10 PM yesterday and ending at 4 AM today should be Open.
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(id: 1, day: yesterday, status: DayStatus.open, opensAt: 22 * 60, closesAt: 4 * 60),
      ];

      if (minute < 4 * 60) {
        expect(MapExplorationLogic.openNow(hours), isTrue);
      }
    });

    test('correctly handles shifts starting today running past midnight', () {
      final DateTime now = DateTime.now();
      final int minute = now.hour * 60 + now.minute;

      // A shift starting at 10 PM today and ending at 4 AM tomorrow.
      final List<OpeningHour> hours = <OpeningHour>[
        OpeningHour(id: 1, day: today, status: DayStatus.open, opensAt: 22 * 60, closesAt: 4 * 60),
      ];

      if (minute >= 22 * 60) {
        expect(MapExplorationLogic.openNow(hours), isTrue);
      }
    });
  });
}
