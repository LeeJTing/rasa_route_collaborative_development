import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_knowledge_logic.dart';

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

  test('finds the regional Hokkien Mee name collision', () {
    final collision = logic.findNameCollision(
      catalogue: <LocalFood>[
        food(
          id: 32,
          name: 'Prawn Noodle',
          synonyms: <String>['Penang Hokkien Mee', 'Har Mee', 'Prawn Mee'],
        ),
        food(id: 31, name: 'Hokkien Mee', synonyms: <String>['KL Hokkien Mee']),
      ],
      foodId: 32,
    );

    expect(collision?.id, 31);
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
}
