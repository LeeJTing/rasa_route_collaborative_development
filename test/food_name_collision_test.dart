import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_knowledge_logic.dart';
import 'package:rasa_route_collaborative_development/views/food_detail_view/widgets/food_name_collision_card.dart';

LocalFood food({
  required int id,
  required String name,
  List<String> synonyms = const <String>[],
}) => LocalFood(
  id: id,
  name: name,
  description: '',
  origin: '',
  culturalBackground: '',
  ingredients: '',
  category: '',
  cookingStyle: '',
  mealType: '',
  foodType: 'Food',
  synonyms: synonyms,
);

void main() {
  final FoodKnowledgeLogic logic = FoodKnowledgeLogic();

  test('Prawn Noodle is not ambiguous just because it lists Hokkien Mee', () {
    final collision = logic.findNameCollision(
      catalogue: <LocalFood>[
        food(
          id: 32,
          name: 'Prawn Noodle',
          synonyms: <String>['Hokkien Mee', 'Penang Hokkien Mee'],
        ),
        food(id: 31, name: 'Hokkien Mee', synonyms: <String>['KL Hokkien Mee']),
      ],
      foodId: 32,
    );

    expect(collision, isNull);
  });

  test('Hokkien Mee is ambiguous when another food lists it as a synonym', () {
    final collision = logic.findNameCollision(
      catalogue: <LocalFood>[
        food(
          id: 32,
          name: 'Prawn Noodle',
          synonyms: <String>['Hokkien Mee', 'Penang Hokkien Mee'],
        ),
        food(id: 31, name: 'Hokkien Mee', synonyms: <String>['KL Hokkien Mee']),
      ],
      foodId: 31,
    );

    expect(collision?.id, 32);
  });

  test('uses exact whole-name aliases for other foods too', () {
    final catalogue = <LocalFood>[
      food(id: 1, name: 'Cendol'),
      food(id: 2, name: 'Nyonya Cendol', synonyms: <String>[' CENDOL ']),
      food(id: 3, name: 'Cendol Pulut', synonyms: <String>['Iced Cendol']),
    ];

    expect(logic.findNameCollision(catalogue: catalogue, foodId: 1)?.id, 2);
    expect(logic.findNameCollision(catalogue: catalogue, foodId: 2), isNull);
    expect(logic.findNameCollision(catalogue: catalogue, foodId: 3), isNull);
  });

  test('does not collide unrelated noodle names', () {
    final collision = logic.findNameCollision(
      catalogue: <LocalFood>[
        food(id: 1, name: 'Prawn Noodle'),
        food(id: 2, name: 'Curry Mee'),
      ],
      foodId: 1,
    );

    expect(collision, isNull);
  });

  testWidgets('ordering caution names the open food before the alternate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodNameCollisionCard(
            currentFoodName: 'Hokkien Mee',
            alternateFood: food(id: 32, name: 'Prawn Noodle'),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Ordering "Hokkien Mee" may refer to "Prawn Noodle"'),
      findsOneWidget,
    );
  });
}
