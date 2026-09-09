import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_pairing.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/pronunciation_playback_result.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/food_detail_view_model.dart';

void main() {
  group('FoodDetailViewModel stress', () {
    test('latest food wins when detail requests finish out of order', () async {
      final Completer<LocalFood> older = Completer<LocalFood>();
      final Completer<LocalFood> latest = Completer<LocalFood>();
      final _FakeFoodLogic logic = _FakeFoodLogic(
        details: <int, Future<LocalFood>>{1: older.future, 2: latest.future},
      );
      final FoodDetailViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);

      final Future<void> olderLoad = viewModel.loadFood(1);
      final Future<void> latestLoad = viewModel.loadFood(2);
      latest.complete(_food(2, 'Latest food'));
      await latestLoad;
      older.complete(_food(1, 'Old food'));
      await olderLoad;

      expect(viewModel.food?.id, 2);
      expect(viewModel.food?.name, 'Latest food');
    });

    test(
      'late favourite response cannot modify a newly selected food',
      () async {
        final Completer<bool> favourite = Completer<bool>();
        final _FakeFoodLogic logic = _FakeFoodLogic(
          details: <int, Future<LocalFood>>{
            1: Future<LocalFood>.value(_food(1, 'First food')),
            2: Future<LocalFood>.value(_food(2, 'Second food')),
          },
          favouriteResult: favourite.future,
        );
        final FoodDetailViewModel viewModel = _TestViewModel(logic);
        addTearDown(viewModel.dispose);
        await viewModel.loadFood(1);

        final Future<String?> update = viewModel.toggleLike();
        await viewModel.loadFood(2);
        favourite.complete(true);
        await update;

        expect(viewModel.food?.id, 2);
        expect(viewModel.isLiked, isFalse);
      },
    );

    test('repeated pairing retry keeps only the newest response', () async {
      final Completer<List<FoodPairing>> older = Completer<List<FoodPairing>>();
      final Completer<List<FoodPairing>> latest =
          Completer<List<FoodPairing>>();
      final _FakeFoodLogic logic = _FakeFoodLogic(
        details: <int, Future<LocalFood>>{
          1: Future<LocalFood>.value(_food(1, 'Prawn Noodle')),
        },
        pairings: <Future<List<FoodPairing>>>[
          Future<List<FoodPairing>>.value(const <FoodPairing>[]),
          older.future,
          latest.future,
        ],
      );
      final FoodDetailViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);
      await viewModel.loadFood(1);

      final Future<void> olderLoad = viewModel.loadPairings();
      final Future<void> latestLoad = viewModel.loadPairings();
      latest.complete(<FoodPairing>[_pairing(3, 'Latest pairing')]);
      await latestLoad;
      older.complete(<FoodPairing>[_pairing(2, 'Old pairing')]);
      await olderLoad;

      expect(viewModel.pairings.single.pairedLocalFoodId, 3);
    });

    test(
      'failed navigation clears the previous food instead of showing stale data',
      () async {
        final Completer<LocalFood> failedDetail = Completer<LocalFood>();
        final _FakeFoodLogic logic = _FakeFoodLogic(
          details: <int, Future<LocalFood>>{
            1: Future<LocalFood>.value(_food(1, 'First food')),
            2: failedDetail.future,
          },
        );
        final FoodDetailViewModel viewModel = _TestViewModel(logic);
        addTearDown(viewModel.dispose);
        await viewModel.loadFood(1);

        final Future<void> failedLoad = viewModel.loadFood(2);
        failedDetail.completeError(Exception('Local food not found.'));
        await failedLoad;

        expect(viewModel.food, isNull);
        expect(viewModel.hasError, isTrue);
        expect(viewModel.errorMessage, 'Local food not found.');
      },
    );

    test(
      'optional section failure keeps core food and shows dietary caution',
      () async {
        final _FakeFoodLogic logic = _FakeFoodLogic(
          details: <int, Future<LocalFood>>{
            1: Future<LocalFood>.value(_food(1, 'Prawn Noodle')),
          },
          failOptionalSections: true,
        );
        final FoodDetailViewModel viewModel = _TestViewModel(logic);
        addTearDown(viewModel.dispose);

        await viewModel.loadFood(1);

        expect(viewModel.food?.id, 1);
        expect(viewModel.hasError, isFalse);
        expect(viewModel.similarFoods, isEmpty);
        expect(
          viewModel.allergyWarning,
          contains('Dietary information is unavailable'),
        );
      },
    );

    test('late pronunciation result does not message the next food', () async {
      final Completer<PronunciationPlaybackResult> pronunciation =
          Completer<PronunciationPlaybackResult>();
      final _FakeFoodLogic logic = _FakeFoodLogic(
        details: <int, Future<LocalFood>>{
          1: Future<LocalFood>.value(_food(1, 'First food')),
          2: Future<LocalFood>.value(_food(2, 'Second food')),
        },
        pronunciationResult: pronunciation.future,
      );
      final FoodDetailViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);
      await viewModel.loadFood(1);

      final Future<void> playback = viewModel.playPronunciation();
      await viewModel.loadFood(2);
      pronunciation.complete(PronunciationPlaybackResult.deviceVoice);
      await playback;

      expect(viewModel.takePronunciationMessage(), isNull);
    });
  });
}

class _TestViewModel extends FoodDetailViewModel {
  _TestViewModel(this.logic);

  final FoodLogicFacade logic;

  @override
  FoodLogicFacade createFoodLogic() => logic;
}

class _FakeFoodLogic extends FoodLogicFacade {
  _FakeFoodLogic({
    required this.details,
    this.favouriteResult,
    this.pairings = const <Future<List<FoodPairing>>>[],
    this.failOptionalSections = false,
    this.pronunciationResult,
  });

  final Map<int, Future<LocalFood>> details;
  final Future<bool>? favouriteResult;
  final List<Future<List<FoodPairing>>> pairings;
  final bool failOptionalSections;
  final Future<PronunciationPlaybackResult>? pronunciationResult;
  int pairingCalls = 0;

  @override
  Future<LocalFood> getFoodDetails(int foodId) => details[foodId]!;

  @override
  Future<LocalFood?> detectNameCollision(int foodId) async {
    if (failOptionalSections) throw Exception('collision unavailable');
    return null;
  }

  @override
  Future<String?> dietaryWarning(int foodId) async {
    if (failOptionalSections) throw Exception('dietary unavailable');
    return null;
  }

  @override
  Future<List<LocalFood>> getSimilarFoods(int foodId) async {
    if (failOptionalSections) throw Exception('similar unavailable');
    return const <LocalFood>[];
  }

  @override
  Future<List<LocalFood>> getLocalFoods() async {
    if (failOptionalSections) throw Exception('catalogue unavailable');
    return const <LocalFood>[];
  }

  @override
  Future<List<FoodPairing>> getFoodPairingRecommendations(int foodId) {
    if (pairings.isEmpty) return Future<List<FoodPairing>>.value(const []);
    return pairings[pairingCalls++];
  }

  @override
  Future<bool> toggleFavouriteFood(int foodId) =>
      favouriteResult ?? Future<bool>.value(true);

  @override
  Future<PronunciationPlaybackResult> playPronunciation(LocalFood food) =>
      pronunciationResult ??
      Future<PronunciationPlaybackResult>.value(
        PronunciationPlaybackResult.curatedAudio,
      );
}

LocalFood _food(int id, String name) => LocalFood(
  id: id,
  name: name,
  description: 'Description',
  origin: 'Origin',
  culturalBackground: 'Background',
  ingredients: 'Ingredients',
  category: 'Chinese',
  cookingStyle: 'Boiled',
  mealType: 'All-Day Dining',
  foodType: 'Food',
);

FoodPairing _pairing(int pairedFoodId, String name) => FoodPairing(
  localFoodId: 1,
  pairedLocalFoodId: pairedFoodId,
  pairedFoodName: name,
  rank: 1,
  matchPercentage: 90,
  reason: 'Reason',
  dietaryStatus: FoodPairingDietaryStatus.compatible,
);
