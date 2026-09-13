import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/dietary_conflict_warning.dart';

/// The stored restriction names are the phrase "No ..." ("No Pork", "No
/// Peanuts") - the warning sentence must drop that prefix, because it
/// already says "avoids".
void main() {
  testWidgets('drops the "No " prefix from the restriction names', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DietaryConflictWarning(
            conflicts: <String>['No Peanuts', 'No Beef'],
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Your profile avoids: Peanuts, Beef. This dish may not suit you.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('No Peanuts'), findsNothing);
  });

  test('label strips the prefix, whatever its case', () {
    expect(DietaryConflictWarning.label('No Peanuts'), 'Peanuts');
    expect(DietaryConflictWarning.label('no pork'), 'pork');
    // Names that are not a "No ..." phrase stay as they are.
    expect(DietaryConflictWarning.label('Vegetarian'), 'Vegetarian');
    expect(DietaryConflictWarning.label('None'), 'None');
  });
}
