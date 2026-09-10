import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_knowledge_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/food_repository_facade.dart';

void main() {
  group('Food Detail dietary warning', () {
    test(
      'combines restrictions into one sentence and removes duplicates',
      () async {
        final FoodKnowledgeLogic logic = _TestFoodKnowledgeLogic(
          _FakeFoodRepository(<DietaryRestriction>[
            const DietaryRestriction(id: 1, name: 'No Eggs'),
            const DietaryRestriction(id: 2, name: 'No Pork'),
            const DietaryRestriction(id: 3, name: ' no eggs '),
          ]),
        );

        expect(
          await logic.dietaryWarning(32),
          'Contains or may include: Eggs, Pork.',
        );
      },
    );

    test(
      'returns no warning when the food has no linked restrictions',
      () async {
        final FoodKnowledgeLogic logic = _TestFoodKnowledgeLogic(
          _FakeFoodRepository(const <DietaryRestriction>[]),
        );

        expect(await logic.dietaryWarning(32), isNull);
      },
    );
  });
}

class _TestFoodKnowledgeLogic extends FoodKnowledgeLogic {
  _TestFoodKnowledgeLogic(this.fakeRepository);

  final FoodRepositoryFacade fakeRepository;

  @override
  FoodRepositoryFacade createRepository() => fakeRepository;
}

class _FakeFoodRepository extends FoodRepositoryFacade {
  _FakeFoodRepository(this.restrictions);

  final List<DietaryRestriction> restrictions;

  @override
  Future<List<DietaryRestriction>> foodDietaryRestrictions(int foodId) async =>
      restrictions;
}
