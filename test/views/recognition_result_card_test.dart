import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/views/food_recognition_view/widgets/recognition_result_card.dart';

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
    'the mismatch warning and keep button both name the recognised dish',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecognitionResultCard(
              food: _food('Murtabak'),
              nameMismatch: true,
              typedName: 'roti canai',
              onDismissNameMismatch: () {},
              foodNameMaxLength: LandmarkSubmissionLogic.maxFoodNameLength,
              foodNameWarning: (_) => null,
            ),
          ),
        ),
      );

      // Two names only: the typed claim (rejected) and the recognised dish
      // that is actually kept. The verification call's raw observation must
      // never surface as a third name - it used to make the warning look
      // like the app had forgotten the detected dish.
      expect(
        find.textContaining("doesn't look like 'roti canai'"),
        findsOneWidget,
      );
      expect(
        find.textContaining("it looks more like 'Murtabak'"),
        findsOneWidget,
      );
      expect(find.textContaining("Keep 'Murtabak'"), findsOneWidget);
      expect(find.textContaining('Roti John'), findsNothing);
    },
  );

  testWidgets(
    'the manual name field stops at 50 characters and warns from 45',
    (tester) async {
      final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecognitionResultCard(
              food: _food('Murtabak'),
              onEnterName: (_) {},
              foodNameMaxLength: LandmarkSubmissionLogic.maxFoodNameLength,
              foodNameWarning: logic.foodNameLengthWarning,
            ),
          ),
        ),
      );

      // The field only exists once the collapsible entry is opened.
      await tester.tap(find.text('Wrong dish? Type the name'));
      await tester.pumpAndSettle();
      final Finder field = find.byType(TextField);

      // 44 characters: below the warn zone, nothing shown.
      await tester.enterText(field, 'a' * 44);
      await tester.pump();
      expect(find.textContaining('should stay under'), findsNothing);

      // 45 characters: the shared logic rule's message appears.
      await tester.enterText(field, 'a' * 45);
      await tester.pump();
      expect(find.textContaining('should stay under 50'), findsOneWidget);
      expect(find.textContaining('currently 45'), findsOneWidget);

      // Past the cap the input is truncated to 50 - the field can never
      // hold more than the rule allows, no matter what is pasted in.
      await tester.enterText(field, 'a' * 60);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text.length, 50);
    },
  );
}
