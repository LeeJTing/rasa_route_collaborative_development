import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_navigator.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_routes.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_recognition_result.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_recognition_logic.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/food_recognition_view_model.dart';
import 'package:rasa_route_collaborative_development/view_models/landmark_detail_view_model.dart';

/// Fake recognition logic - replaces the whole logic+Gemini stack so the
/// ViewModel's branching (multiple results / not-local / single) can be
/// tested in isolation.
class _FakeFoodRecognitionLogic extends FoodRecognitionLogic {
  Future<FoodRecognitionResult> Function(List<int>)? onRecognize;
  Future<({LocalFood food, double priceMin, double priceMax})> Function(
    List<int> bytes,
    String name,
  )?
  onResolveByName;

  @override
  Future<FoodRecognitionResult> recognizeFood(List<int> imageBytes) =>
      onRecognize!(imageBytes);

  @override
  Future<({LocalFood food, double priceMin, double priceMax})> resolveByName(
    List<int> imageBytes,
    String name,
  ) => onResolveByName!(imageBytes, name);
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

FoodRecognitionViewModel _buildViewModel(_FakeFoodRecognitionLogic logic) =>
    FoodRecognitionViewModel(
      landmarkLogic: LandmarkLogicFacade(foodRecognition: logic),
    );

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
        logic.onResolveByName = (List<int> bytes, String name) async =>
            (food: _food('Roti Canai'), priceMin: 2.0, priceMax: 8.0);
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
  });

  group('FoodRecognitionViewModel.enterFoodName (manual fallback)', () {
    test('resolves a typed name and shows the single result', () async {
      final _FakeFoodRecognitionLogic logic = _FakeFoodRecognitionLogic();
      final LocalFood murtabak = _food('Murtabak');
      logic.onRecognize = (_) async => FoodRecognitionResult(
        isLocalFood: true,
        candidates: <LocalFood>[_food('Roti Canai')],
      );
      logic.onResolveByName = (List<int> bytes, String name) async =>
          (food: murtabak, priceMin: 0.0, priceMax: 0.0);
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
      logic.onResolveByName = (List<int> bytes, String name) async =>
          (food: _food(name), priceMin: 0.0, priceMax: 0.0);
      final FoodRecognitionViewModel vm = _buildViewModel(logic);
      await vm.captureAndRecognize(_image());
      expect(vm.hasMultipleResults, isTrue); // picker showing

      await vm.enterFoodName('Murtabak');

      expect(vm.hasMultipleResults, isFalse);
      expect(vm.recognizedFood?.name, 'Murtabak');
    });
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

  group('LandmarkDetailViewModel', () {
    test('blocks add-landmark for a non-local food', () {
      final LandmarkDetailViewModel vm = LandmarkDetailViewModel();
      vm.setRecognizedFood(_food('X'));
      vm.setIsLocalFood(false);

      expect(vm.isLocalFood, isFalse);
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
