import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_navigator.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_routes.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_recognition_result.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_recognition_logic.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/food_recognition_view_model.dart';
import 'package:rasa_route_collaborative_development/view_models/landmark_detail_view_model.dart';

/// Fake recognition logic - replaces the whole logic+Gemini stack so the
/// ViewModel's branching (multiple results / not-local / single) can be
/// tested in isolation.
class _FakeFoodRecognitionLogic extends FoodRecognitionLogic {
  Future<FoodRecognitionResult> Function(List<int>)? onRecognize;
  Future<
    ({
      LocalFood food,
      double priceMin,
      double priceMax,
      bool nameMatchesPhoto,
      double matchConfidence,
      bool isLocalFood,
      bool fitsCatalogueCategory,
      String observedFood,
      List<String> dietaryRestrictions,
    })
  >
  Function(List<int> bytes, String name)?
  onResolveByName;
  Future<
    ({
      LocalFood food,
      double priceMin,
      double priceMax,
      bool fitsCatalogueCategory,
      List<String> dietaryRestrictions,
    })
  >
  Function(List<int> bytes, String name)?
  onEnrichCandidate;

  /// Dietary restriction names the signed-in tourist holds - empty by default
  /// so unrelated tests never see a conflict warning.
  List<String> userRestrictions = const <String>[];

  @override
  Future<List<String>> userDietaryRestrictionNames() async => userRestrictions;

  @override
  Future<FoodRecognitionResult> recognizeFood(List<int> imageBytes) =>
      onRecognize!(imageBytes);

  @override
  Future<
    ({
      LocalFood food,
      double priceMin,
      double priceMax,
      bool nameMatchesPhoto,
      double matchConfidence,
      bool isLocalFood,
      bool fitsCatalogueCategory,
      String observedFood,
      List<String> dietaryRestrictions,
    })
  >
  resolveByName(List<int> imageBytes, String name) =>
      onResolveByName!(imageBytes, name);

  @override
  Future<
    ({
      LocalFood food,
      double priceMin,
      double priceMax,
      bool fitsCatalogueCategory,
      List<String> dietaryRestrictions,
    })
  >
  enrichCandidate(List<int> imageBytes, String name) =>
      onEnrichCandidate!(imageBytes, name);
}

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

XFile _image() => XFile.fromData(
  Uint8List.fromList(<int>[1, 2, 3]),
  mimeType: 'image/jpeg',
  name: 'test.jpg',
);

/// A known [TouristLocation] fix for the location-gate tests (A9).
TouristLocation _fix(double latitude, double longitude) => TouristLocation(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: 10,
  capturedAt: DateTime.now(),
);

FoodRecognitionViewModel _buildViewModel(_FakeFoodRecognitionLogic logic) =>
    _TestFoodRecognitionViewModel(logic);

class _TestLandmarkLogicFacade extends LandmarkLogicFacade {
  _TestLandmarkLogicFacade(this.logic);

  final FoodRecognitionLogic logic;

  @override
  FoodRecognitionLogic createFoodRecognition() => logic;
}

class _TestFoodRecognitionViewModel extends FoodRecognitionViewModel {
  _TestFoodRecognitionViewModel(this.logic);

  final FoodRecognitionLogic logic;

  @override
  LandmarkLogicFacade createLandmarkLogic() => _TestLandmarkLogicFacade(logic);

  @override
  Duration get minimumLoadingDuration => Duration.zero;
}

void main() {
  setUp(LandmarkDraftHandoff().clear);

  group('FoodRecognitionViewModel.captureAndRecognize', () {
    test(
      'surfaces a top-3 picker when Gemini returns multiple candidates',
      () async {
        final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
        logic.onRecognize = (_) async => FoodRecognitionResult(
          isLocalFood: true,
          candidates: <LocalFood>[_food('Murtabak'), _food('Roti Canai')],
        );
        final FoodRecognitionViewModel vm = _buildViewModel(logic);

        await vm.captureAndRecognize(_image());

        expect(vm.isLocalFood, isTrue);
        expect(vm.hasMultipleResults, isTrue);
        expect(vm.recognizedFood, isNull);
        expect(vm.multipleResults.length, 2);
      },
    );

    test('keeps a non-local food but flags isLocalFood=false', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      final LocalFood nonLocal = _food('Some Foreign Dish');
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: false,
        candidates: <LocalFood>[nonLocal],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);

      await vm.captureAndRecognize(_image());

      expect(vm.isLocalFood, isFalse);
      expect(vm.recognizedFood, nonLocal);
      expect(vm.hasMultipleResults, isFalse);
    });

    test('sets a confident local single result', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      final LocalFood food = _food('Murtabak');
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[food],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);

      await vm.captureAndRecognize(_image());

      expect(vm.isLocalFood, isTrue);
      expect(vm.recognizedFood, food);
      expect(vm.hasMultipleResults, isFalse);
    });

    test(
      'selectFromMultiple enriches the picked candidate with full details',
      () async {
        final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
        final LocalFood murtabak = _food('Murtabak');
        final LocalFood roti = _food('Roti Canai');
        logic.onRecognize = (_) async => FoodRecognitionResult(
          isLocalFood: true,
          candidates: <LocalFood>[murtabak, roti],
        );
        // The picked candidate is resolved to its full record (catalogue
        // match, else Gemini name+image analysis) with its price range - so
        // "View Details" is never left name-only.
        logic.onEnrichCandidate = (List<int> bytes, String name) async => (
          food: _food('Roti Canai'),
          priceMin: 2.0,
          priceMax: 8.0,
          fitsCatalogueCategory: true,
          dietaryRestrictions: const <String>[],
        );
        final FoodRecognitionViewModel vm = _buildViewModel(logic);
        await vm.captureAndRecognize(_image());
        expect(vm.hasMultipleResults, isTrue); // picker showing

        await vm.selectFromMultiple(roti);

        expect(vm.hasMultipleResults, isFalse);
        expect(vm.isLocalFood, isTrue);
        expect(vm.recognizedFood?.name, 'Roti Canai');
        expect(vm.recognizedFood?.description, 'Description of Roti Canai');
        expect(vm.priceMin, 2.0);
        expect(vm.priceMax, 8.0);
      },
    );

    test('warns when the recognised food conflicts with the tourist\'s '
        'dietary restrictions but still keeps it addable', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.userRestrictions = <String>['No Pork'];
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Murtabak')],
        dietaryRestrictions: const <String>['No Pork', 'High Calorie'],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.onInit();

      await vm.captureAndRecognize(_image());

      expect(vm.recognizedFood?.name, 'Murtabak');
      expect(vm.isLocalFood, isTrue);
      // Warning present but non-blocking - the food is still addable.
      expect(vm.hasDietaryConflict, isTrue);
      expect(vm.dietaryConflicts, <String>['No Pork']);
      vm.dispose();
    });

    test('does not warn when no user restriction matches the food', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.userRestrictions = <String>['No Beef'];
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Murtabak')],
        dietaryRestrictions: const <String>['No Pork'],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.onInit();

      await vm.captureAndRecognize(_image());

      expect(vm.hasDietaryConflict, isFalse);
      expect(vm.dietaryConflicts, isEmpty);
      vm.dispose();
    });
  });

  group('FoodRecognitionViewModel.enterFoodName (manual fallback)', () {
    test('resolves a typed name and shows the single result', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      final LocalFood murtabak = _food('Murtabak');
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Roti Canai')],
      );
      logic.onResolveByName = (List<int> bytes, String name) async => (
        food: murtabak,
        priceMin: 0.0,
        priceMax: 0.0,
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        isLocalFood: true,
        fitsCatalogueCategory: true,
        observedFood: '',
        dietaryRestrictions: const <String>[],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image()); // populates _capturedImage

      await vm.enterFoodName('Murtabak');

      expect(vm.recognizedFood, murtabak);
      expect(vm.hasMultipleResults, isFalse);
      expect(vm.isLocalFood, isTrue);
    });

    test('replaces the picker candidates with the typed result', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('A'), _food('B')],
      );
      logic.onResolveByName = (List<int> bytes, String name) async => (
        food: _food(name),
        priceMin: 0.0,
        priceMax: 0.0,
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        isLocalFood: true,
        fitsCatalogueCategory: true,
        observedFood: '',
        dietaryRestrictions: const <String>[],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());
      expect(vm.hasMultipleResults, isTrue); // picker showing

      await vm.enterFoodName('Murtabak');

      expect(vm.hasMultipleResults, isFalse);
      expect(vm.recognizedFood?.name, 'Murtabak');
    });

    test('keeps the detected food and warns when the typed name does not match '
        'the photo', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Roti Canai')],
      );
      // Photo was detected as 'Roti Canai' but the tourist types
      // 'Nasi Lemak': Gemini can't confirm it, so the detected food must
      // stay and a mismatch warning must show instead of renaming.
      logic.onResolveByName = (List<int> bytes, String name) async => (
        food: _food(name),
        priceMin: 0.0,
        priceMax: 0.0,
        nameMatchesPhoto: false,
        matchConfidence: 0.9,
        isLocalFood: false,
        fitsCatalogueCategory: true,
        observedFood: 'Roti Canai',
        dietaryRestrictions: const <String>[],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image()); // populates _capturedImage

      await vm.enterFoodName('Nasi Lemak');

      // The displayed name did NOT change to what was typed.
      expect(vm.recognizedFood?.name, 'Roti Canai');
      expect(vm.nameMismatch, isTrue);
      expect(vm.observedFoodName, 'Roti Canai');
      expect(vm.typedName, 'Nasi Lemak');
      // The detected food's own verdict stays.
      expect(vm.isLocalFood, isTrue);

      // Dismiss keeps the detected food and drops the typed name.
      vm.dismissNameMismatch();
      expect(vm.recognizedFood?.name, 'Roti Canai');
      expect(vm.nameMismatch, isFalse);
      expect(vm.typedName, isNull);
    });

    test('a mismatched typed name can never be applied - keeping the detected '
        'food is the only action', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Roti Canai')],
      );
      logic.onResolveByName = (List<int> bytes, String name) async => (
        food: _food(name),
        priceMin: 0.0,
        priceMax: 0.0,
        nameMatchesPhoto: false,
        matchConfidence: 0.9,
        isLocalFood: false,
        fitsCatalogueCategory: true,
        observedFood: 'Roti Canai',
        dietaryRestrictions: const <String>[],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());
      await vm.enterFoodName('Nasi Lemak');

      // The mismatch is surfaced - the typed name is only held for the
      // warning ("this photo doesn't look like Nasi Lemak") ...
      expect(vm.nameMismatch, isTrue);
      expect(vm.observedFoodName, 'Roti Canai');
      expect(vm.typedName, 'Nasi Lemak');
      // ... and the detected food can never be replaced by the typed name.
      expect(vm.recognizedFood?.name, 'Roti Canai');
      expect(vm.isLocalFood, isTrue);

      // The only action is keeping the detected food.
      vm.dismissNameMismatch();
      expect(vm.recognizedFood?.name, 'Roti Canai');
      expect(vm.nameMismatch, isFalse);
      expect(vm.typedName, isNull);
    });

    test(
      'a re-submitted name that resolves to a snack is kept but not addable',
      () async {
        final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
        logic.onRecognize = (_) async => FoodRecognitionResult(
          isLocalFood: true,
          candidates: <LocalFood>[_food('Roti Canai')],
        );
        // The tourist changes the name to a snack (Tam Tam) and Gemini confirms
        // the photo shows it - the category gate must be re-evaluated for the
        // NEW name, not left stale from the previous recognition.
        logic.onResolveByName = (List<int> bytes, String name) async => (
          food: _food('Tam Tam'),
          priceMin: 0.0,
          priceMax: 0.0,
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          isLocalFood: true,
          fitsCatalogueCategory: false,
          observedFood: '',
          dietaryRestrictions: const <String>[],
        );
        final FoodRecognitionViewModel vm = _buildViewModel(logic);
        await vm.captureAndRecognize(_image()); // populates _capturedImage

        await vm.enterFoodName('Tam Tam');

        // The typed snack becomes the recognised food ...
        expect(vm.recognizedFood?.name, 'Tam Tam');
        // ... but it is Malaysian-yet-not-addable.
        expect(vm.isLocalFood, isTrue);
        expect(vm.fitsCatalogueCategory, isFalse);
        // And "Add New Landmark" is blocked.
        vm.proceedToAddLandmark();
        expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
      },
    );
  });

  group('non-local food must never become a landmark', () {
    test('proceedToAddLandmark is a no-op for a non-local food', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: false,
        candidates: <LocalFood>[_food('X')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      vm.proceedToAddLandmark();

      // The hand-off is never populated, and no navigation happens (the guard
      // returns before AppNavigator is touched).
      expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
    });

    test('confirmFoodAndReturn is a no-op for a non-local food', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: false,
        candidates: <LocalFood>[_food('X')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      vm.setPurpose(FoodRecognitionPurpose.additionalFood);
      await vm.captureAndRecognize(_image());

      // Without the guard this would call AppNavigator.pop (and throw, since
      // no navigator is built) - completing normally proves the guard holds.
      expect(vm.confirmFoodAndReturn, returnsNormally);
    });

    test('proceedToAddLandmark is a no-op for a Malaysian snack', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        fitsCatalogueCategory: false,
        candidates: <LocalFood>[_food('Tam Tam')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      vm.proceedToAddLandmark();

      // The hand-off is never populated - the snack is a Malaysian product,
      // not an addable landmark.
      expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
    });
  });

  group('local food proceeds to Add Landmark', () {
    testWidgets('hands the recognized food to the hand-off', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppNavigator.navigatorKey,
          routes: <String, WidgetBuilder>{
            AppRoutes.addLandmark: (BuildContext _) => const SizedBox(),
          },
          home: const SizedBox(),
        ),
      );

      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      final LocalFood food = _food('Murtabak');
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[food],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      vm.proceedToAddLandmark();

      expect(LandmarkDraftHandoff().pendingRecognizedFood, food);
      expect(LandmarkDraftHandoff().pendingIsLocalFood, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('Add New Landmark blocked at sea / outside Malaysia (A9)', () {
    test('a known fix at sea (Straits of Malacca) blocks adding', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Murtabak')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      // The "At sea" mock preset - recognised food is still shown, but the
      // tourist must never be able to take it to the Add Landmark form.
      vm.onCurrentLocationChanged(_fix(3.0, 100.2));

      expect(vm.isAddLandmarkBlockedByLocation, isTrue);
      expect(vm.addLandmarkLocationBlockMessage, isNotNull);
      vm.proceedToAddLandmark();
      expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
    });

    test('a known fix outside Malaysia (Singapore) blocks adding', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Murtabak')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      // The "Outside MY" mock preset.
      vm.onCurrentLocationChanged(_fix(1.3521, 103.8198));

      expect(vm.isAddLandmarkBlockedByLocation, isTrue);
      vm.proceedToAddLandmark();
      expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
    });

    test('a fix on Malaysian land (KL) does not block adding', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Murtabak')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      vm.onCurrentLocationChanged(_fix(3.1390, 101.6869));

      expect(vm.isAddLandmarkBlockedByLocation, isFalse);
      expect(vm.addLandmarkLocationBlockMessage, isNull);
    });

    test('no fix yet does not block adding (existing behaviour)', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Murtabak')],
      );
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());

      expect(vm.currentLocation.isKnown, isFalse);
      expect(vm.isAddLandmarkBlockedByLocation, isFalse);
    });
  });

  group('LandmarkDetailViewModel', () {
    test('blocks add-landmark for a non-local food', () {
      final LandmarkDetailViewModel vm = LandmarkDetailViewModel();
      vm.setRecognizedFood(_food('X'));
      vm.setIsLocalFood(false);

      expect(vm.isLocalFood, isFalse);
      expect(vm.proceedToAddLandmark, returnsNormally);
      expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
    });

    test(
      'blocks add-landmark for a Malaysian snack (fitsCatalogueCategory=false)',
      () {
        final LandmarkDetailViewModel vm = LandmarkDetailViewModel();
        vm.setRecognizedFood(_food('Tam Tam'));
        vm.setIsLocalFood(true);
        vm.setFitsCatalogueCategory(false);

        expect(vm.fitsCatalogueCategory, isFalse);
        expect(vm.proceedToAddLandmark, returnsNormally);
        expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
      },
    );

    test('blocks add-landmark while the fix is at sea / outside Malaysia', () {
      final LandmarkDetailViewModel vm = LandmarkDetailViewModel();
      vm.setRecognizedFood(_food('Murtabak'));
      vm.setIsLocalFood(true);
      vm.setFitsCatalogueCategory(true);

      // The "At sea" mock preset - a locally-recognised food, but the detail
      // screen must not offer to add it as a landmark.
      vm.onCurrentLocationChanged(_fix(3.0, 100.2));

      expect(vm.isAddLandmarkBlockedByLocation, isTrue);
      expect(vm.addLandmarkLocationBlockMessage, isNotNull);
      expect(vm.proceedToAddLandmark, returnsNormally);
      expect(LandmarkDraftHandoff().pendingRecognizedFood, isNull);
    });

    testWidgets('passes a local food onward to the hand-off', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppNavigator.navigatorKey,
          routes: <String, WidgetBuilder>{
            AppRoutes.addLandmark: (BuildContext _) => const SizedBox(),
          },
          home: const SizedBox(),
        ),
      );

      final LandmarkDetailViewModel vm = LandmarkDetailViewModel();
      final LocalFood food = _food('Murtabak');
      vm.setRecognizedFood(food);

      vm.proceedToAddLandmark();

      expect(LandmarkDraftHandoff().pendingRecognizedFood, food);
      await tester.pumpAndSettle();
    });
  });

  group('LandmarkDraftHandoff.isLocalFood', () {
    test('carries the flag and resets to true after take', () {
      final LandmarkDraftHandoff handoff = LandmarkDraftHandoff();
      handoff.clear();

      handoff.pendingIsLocalFood = false;
      expect(handoff.takeIsLocalFood(), isFalse);
      // A later, unrelated navigation must not inherit the previous value.
      expect(handoff.takeIsLocalFood(), isTrue);
    });
  });
}
