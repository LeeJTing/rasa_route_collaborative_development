import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/views/food_recognition_view/widgets/multiple_results_card.dart';

LocalFood _food(String name) => LocalFood(
  id: 1,
  name: name,
  description: 'Description of $name',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: 'Frying',
  mealType: 'Breakfast',
  foodType: 'Food',
);

void main() {
  testWidgets(
    'the multiple-results card uses the SAME manual entry as the single one',
    (tester) async {
      final List<String> submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultipleResultsCard(
              results: <LocalFood>[_food('Murtabak'), _food('Roti Canai')],
              onSelect: (_) {},
              onEnterName: submitted.add,
              foodNameMaxLength: LandmarkSubmissionLogic.maxFoodNameLength,
              foodNameWarning: (_) => null,
            ),
          ),
        ),
      );

      // Collapsed, exactly like the single-result card: the link - never an
      // always-open field with its own label and inline button.
      expect(find.text('Wrong dish? Type the name'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('None of these?'), findsNothing);

      await tester.tap(find.text('Wrong dish? Type the name'));
      await tester.pumpAndSettle();

      // Opened: the shared field and the same Cancel / Show this food pair
      // the single-result card uses.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  Cendol Jagung  ');
      await tester.tap(find.text('Show this food'));
      await tester.pump();

      // Trimmed, and handed to the same callback the single card uses.
      expect(submitted, <String>['Cendol Jagung']);
    },
  );

  testWidgets('Cancel collapses the manual entry again', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultipleResultsCard(
            results: <LocalFood>[_food('Murtabak')],
            onSelect: (_) {},
            onEnterName: (_) {},
            foodNameMaxLength: LandmarkSubmissionLogic.maxFoodNameLength,
            foodNameWarning: (_) => null,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Wrong dish? Type the name'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Wrong dish? Type the name'), findsOneWidget);
  });
}
