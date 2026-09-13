import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_knowledge_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/food_repository_facade.dart';

void main() {
  test('a list read waits for a Profile deletion still being saved', () async {
    final _DelayedFavouriteRepository repository =
        _DelayedFavouriteRepository();
    final FoodKnowledgeLogic profileLogic = _TestFoodKnowledgeLogic(repository);
    final FoodKnowledgeLogic listLogic = _TestFoodKnowledgeLogic(repository);

    final Future<void> deletion = profileLogic.removeFavouriteFood(1);
    await Future<void>.delayed(Duration.zero);
    expect(repository.favouriteReadCount, 1);

    final Future<Set<int>> refreshedIds = listLogic.favouriteFoodIds();
    final Future<List<LocalFood>> refreshedFoods = listLogic.getLocalFoods();
    await Future<void>.delayed(Duration.zero);
    expect(repository.favouriteReadCount, 1);
    expect(repository.catalogueReadCount, 0);

    repository.finishDeletion();
    await deletion;

    expect(await refreshedIds, isEmpty);
    await refreshedFoods;
    expect(repository.favouriteReadCount, 2);
    expect(repository.catalogueReadCount, 1);
  });

  test('a failed deletion does not block later favourite reads', () async {
    final _DelayedFavouriteRepository repository =
        _DelayedFavouriteRepository();
    final FoodKnowledgeLogic profileLogic = _TestFoodKnowledgeLogic(repository);
    final FoodKnowledgeLogic listLogic = _TestFoodKnowledgeLogic(repository);

    final Future<void> deletion = profileLogic.removeFavouriteFood(1);
    await Future<void>.delayed(Duration.zero);
    final Future<Set<int>> refreshedIds = listLogic.favouriteFoodIds();

    final Future<void> failedAsExpected = expectLater(
      deletion,
      throwsStateError,
    );
    repository.failDeletion();
    await failedAsExpected;
    expect(await refreshedIds, <int>{1});
  });
}

class _TestFoodKnowledgeLogic extends FoodKnowledgeLogic {
  _TestFoodKnowledgeLogic(this.fakeRepository);

  final FoodRepositoryFacade fakeRepository;

  @override
  FoodRepositoryFacade createRepository() => fakeRepository;
}

class _DelayedFavouriteRepository extends FoodRepositoryFacade {
  final Completer<bool> _deletion = Completer<bool>();
  final Set<int> _savedIds = <int>{1};
  int favouriteReadCount = 0;
  int catalogueReadCount = 0;

  @override
  Future<Set<int>> favouriteFoodIds() async {
    favouriteReadCount += 1;
    return Set<int>.of(_savedIds);
  }

  @override
  Future<bool> toggleFavourite(int localFoodId) async {
    await _deletion.future;
    _savedIds.remove(localFoodId);
    return false;
  }

  @override
  Future<List<LocalFood>> getFoods() async {
    catalogueReadCount += 1;
    return const <LocalFood>[];
  }

  void finishDeletion() => _deletion.complete(false);

  void failDeletion() => _deletion.completeError(StateError('delete failed'));
}
