import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/recognised_food_card.dart';

LocalFood _food({String ingredients = ''}) => LocalFood(
  id: 375,
  name: 'Cendol',
  description: 'A chilled dessert',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: ingredients,
  category: 'Nyonya',
  cookingStyle: 'Chilling',
  mealType: 'Dessert',
  foodType: 'Dessert',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('View Details shows the dish ingredients when it has any', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(
          food: _food(
            ingredients:
                'Pandan jelly, coconut milk, palm sugar, shaved ice, '
                'gula Melaka, sweet corn',
          ),
          variant: 'Cendol Jagung',
          collapsible: false,
        ),
      ),
    );

    // The dictionary's ingredients plus the variant's addition - the whole
    // point of the inherit-and-merge rule on `landmark_item.ingredients`.
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.textContaining('sweet corn'), findsOneWidget);
    expect(find.textContaining('Pandan jelly'), findsOneWidget);
  });

  testWidgets('the Ingredients row is hidden when the dish has none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(RecognisedFoodCard(food: _food(), collapsible: false)),
    );

    expect(find.text('Ingredients'), findsNothing);
  });

  testWidgets('on the form card it sits behind the expand arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(
          food: _food(ingredients: 'Pandan jelly, sweet corn'),
          collapsible: true,
        ),
      ),
    );

    expect(find.text('Ingredients'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('Ingredients'), findsOneWidget);
  });
}
