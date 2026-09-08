import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/preference_option_card.dart';

void main() {
  testWidgets('renders a bundled SVG icon asset without error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PreferenceOptionCard(
            label: 'Sweet',
            isSelected: false,
            onTap: _noop,
            iconAsset: 'assets/images/profile/sweet.svg',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Sweet'), findsOneWidget);
  });
}

void _noop() {}
