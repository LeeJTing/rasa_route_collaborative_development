import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/place_menu_section.dart';

/// The collapsible "Local Foods Served (N)" section, shared by the restaurant
/// detail page and the submitted-landmark page so both present their dishes
/// the same way (user request, 2026-09-13).
Future<void> _pump(
  WidgetTester tester, {
  required int itemCount,
  required List<Widget> children,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: PlaceMenuSection(
        itemCount: itemCount,
        emptyMessage: 'No dishes recorded for this landmark yet.',
        children: children,
      ),
    ),
  ),
);

void main() {
  testWidgets('the header counts the dishes and the rows start collapsed', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      itemCount: 2,
      children: const <Widget>[Text('Row A'), Text('Row B')],
    );

    expect(find.text('Local Foods Served (2)'), findsOneWidget);
    expect(find.text('Row A'), findsNothing);

    await tester.tap(find.text('Local Foods Served (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Row A'), findsOneWidget);
    expect(find.text('Row B'), findsOneWidget);
  });

  testWidgets('an empty section says so once it is opened', (
    WidgetTester tester,
  ) async {
    await _pump(tester, itemCount: 0, children: const <Widget>[]);

    expect(find.text('Local Foods Served (0)'), findsOneWidget);

    await tester.tap(find.text('Local Foods Served (0)'));
    await tester.pumpAndSettle();

    expect(
      find.text('No dishes recorded for this landmark yet.'),
      findsOneWidget,
    );
  });
}
