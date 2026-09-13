import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/operating_hours_editor.dart';

void main() {
  testWidgets('an overnight close shows a plain time - no "(+1)" marker', (
    WidgetTester tester,
  ) async {
    // A phone-width surface: the time boxes take a fixed slice of the day
    // row, so whatever they show has to fit that slice.
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperatingHoursEditor(
            operatingHours: const <Weekday, List<OpeningHour>>{
              Weekday.monday: <OpeningHour>[
                OpeningHour(
                  id: 0,
                  day: Weekday.monday,
                  status: DayStatus.open,
                  opensAt: 600, // 10:00
                  closesAt: 1560, // 02:00 the NEXT day (encoded)
                ),
              ],
            },
            onStatusChanged: (_, _) {},
            onRangeTimeChanged: (_, _, _, _) {},
            onAddRange: (_) {},
            onRemoveRange: (_, _) {},
          ),
        ),
      ),
    );

    // The closing box reads exactly like any other time. The next-day
    // meaning rides the VALUE (1560) - it is applied by the ViewModel's
    // `setRangeTime` and written as split rows by `OpeningHoursRows`, so the
    // UI has nothing extra to say.
    expect(
      find.descendant(
        of: find.byType(TimeDropdownField).last, // the closing box
        matching: find.text('02:00'),
      ),
      findsOneWidget,
    );

    // No "(+1)" marker, and no explainer line either - the tourist sees
    // only the times they picked.
    expect(find.textContaining('(+1)'), findsNothing);
    expect(find.textContaining('midnight'), findsNothing);
  });

  testWidgets('the "Copy Monday to All Weekdays" link gets its own line', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperatingHoursEditor(
            operatingHours: const <Weekday, List<OpeningHour>>{
              Weekday.monday: <OpeningHour>[
                OpeningHour(
                  id: 0,
                  day: Weekday.monday,
                  status: DayStatus.open,
                  opensAt: 600, // 10:00
                  closesAt: 1080, // 18:00
                ),
              ],
            },
            onStatusChanged: (_, _) {},
            onRangeTimeChanged: (_, _, _, _) {},
            onAddRange: (_) {},
            onRemoveRange: (_, _) {},
            onCopyMondayToAll: () {},
          ),
        ),
      ),
    );

    // The whole label is on screen...
    final Finder link = find.text('Copy Monday to All Weekdays');
    expect(link, findsOneWidget);

    // ...on its OWN line, left-aligned under the title. Sharing the title's
    // row left the link barely a third of the card on a phone, so the label
    // ellipsized to "Copy Monday to All Week…"; on its own line it has the
    // card's whole width and can never be squeezed again.
    final Finder title = find.text('Operating Hours');
    expect(
      tester.getTopLeft(link).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
    );
    expect(tester.getTopLeft(link).dx, tester.getTopLeft(title).dx);
  });
}
