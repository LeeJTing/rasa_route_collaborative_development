import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/app/routing/map_selection_handoff.dart';
import 'package:rasa_route_collaborative_development/views/landmark_place_detail_view/landmark_place_detail_view.dart';

void main() {
  testWidgets('the app bar never falls back to a bare "Landmark" title', (
    WidgetTester tester,
  ) async {
    // No landmark handed over: the screen loads nothing, so this exercises
    // the state BEFORE a name exists. The bar must still be driven by that
    // state - it used to be a hard-coded "Landmark" (see the screenshot
    // report: it said nothing about which place had been opened, while the
    // catalogue's restaurant page shows the place's own name).
    addTearDown(() => MapSelectionHandoff().pendingLandmarkId = null);
    MapSelectionHandoff().pendingLandmarkId = null;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LandmarkPlaceDetailView()),
    );
    await tester.pump();

    expect(find.text('Landmark Details'), findsOneWidget);
    expect(find.text('Landmark'), findsNothing);
  });
}
