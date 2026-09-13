import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/domain_model/map.dart';
import 'package:rasa_route_collaborative_development/views/dashboard_view/widgets/map_selection_cards.dart';

/// The pin sheet the tourist gets after tapping a marker.
///
/// The landmark half used to be a dead end: the sheet said "Landmark
/// submitted by a tourist" and "Unknown" whatever was on record, because
/// `MapExplorationLogic.pinDetail` skipped landmarks (user report,
/// 2026-09-13). These tests pin the sheet's side of the bargain - it shows
/// what the pin carries and never invents "Unknown" for a landmark.
MapPin _pin({
  MapPinKind kind = MapPinKind.landmark,
  String label = 'HOMETOWN ICE KACANG',
  String? category,
  String? priceRange,
  bool? openNow,
}) => MapPin(
  referenceId: '7',
  kind: kind,
  latitude: 3.1,
  longitude: 101.6,
  label: label,
  weight: 1,
  category: category,
  priceRange: priceRange,
  openNow: openNow,
  distanceMetres: 46,
);

Future<void> _pumpSheet(WidgetTester tester, MapPin pin) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: RestaurantPinSheet(pin: pin, onDismiss: () {}, onOpen: () {}),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a landmark says what kind of place it is, what it costs and its state',
    (WidgetTester tester) async {
      await _pumpSheet(
        tester,
        _pin(category: 'Chinese restaurant', priceRange: 'RM5-8'),
      );

      expect(find.text('Chinese restaurant'), findsOneWidget);
      expect(find.text('RM5-8'), findsOneWidget);
      // Same line a restaurant gets: price, then the state - and "Unknown"
      // when no hours are on record (user request, 2026-09-13).
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.textContaining('submitted by a tourist'), findsNothing);
      expect(find.text('View Landmark'), findsOneWidget);
    },
  );

  testWidgets('a landmark with hours on record says open or closed', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      _pin(category: 'Chinese restaurant', priceRange: 'RM6', openNow: false),
    );

    expect(find.text('Chinese restaurant'), findsOneWidget);
    expect(find.text('RM6'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);

    await _pumpSheet(
      tester,
      _pin(category: 'Chinese restaurant', priceRange: 'RM6', openNow: true),
    );

    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a landmark with nothing on record still says Unknown', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, _pin());

    expect(find.text('HOMETOWN ICE KACANG'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.textContaining('submitted by a tourist'), findsNothing);
    expect(
      find.textContaining('Restaurant from the system catalogue'),
      findsNothing,
    );
  });

  testWidgets('a restaurant without hours still says Unknown', (
    WidgetTester tester,
  ) async {
    // Unchanged behaviour on the restaurant side: the catalogue's own places
    // keep saying that their hours are not on record rather than dropping the
    // line (the `MapPin.openNow` contract).
    await _pumpSheet(
      tester,
      _pin(
        kind: MapPinKind.restaurant,
        label: 'Restoran Ah Wah',
        category: 'Chinese restaurant',
        priceRange: 'RM10-20',
      ),
    );

    expect(find.text('Chinese restaurant'), findsOneWidget);
    expect(find.text('RM10-20'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('View Restaurant'), findsOneWidget);
  });

  testWidgets('a landmark with only a price still says Unknown', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, _pin(priceRange: 'RM5'));

    expect(find.text('RM5'), findsOneWidget);
    expect(find.text('  |  '), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
  });
}
