import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_recognition_result.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/origin_verification.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_recognition_logic.dart';
import 'package:rasa_route_collaborative_development/model/data_models/food_analysis_response.dart';
import 'package:rasa_route_collaborative_development/model/repositories/discovery_repository_facade.dart';
import 'package:rasa_route_collaborative_development/model/repositories/food_knowledge_repository.dart';
import 'package:rasa_route_collaborative_development/model/repositories/food_repository_facade.dart';
import 'package:rasa_route_collaborative_development/model/repositories/recognition_repository.dart';

/// Fake recognition repository - replaces Gemini entirely, so the two-phase
/// orchestration in `FoodRecognitionLogic.recognizeFood` can be exercised
/// without any network call.
class _FakeRecognitionRepository extends RecognitionRepository {
  Future<FoodAnalysisResponse> Function(List<int>)? onIdentify;
  Future<FoodAnalysis> Function(List<int>)? onAnalyzeFull;
  Future<FoodAnalysis> Function(List<int> bytes, String name)? onAnalyzeByName;
  Future<({bool isTypo, String correctedName})> Function(
    String typedName,
    String observedFood,
  )?
  onSpellCheck;
  OriginVerification Function(String)? onVerifyOrigin;

  /// The STORED CATALOGUE RECORD sent with the last full / by-name analysis
  /// call - the curated row the app already matched for that dish, or null
  /// when it had none to send.
  LocalFood? fullStoredDish;
  LocalFood? byNameStoredDish;

  @override
  Future<FoodAnalysisResponse> identifyFoodName(List<int> imageBytes) =>
      onIdentify!(imageBytes);

  @override
  Future<FoodAnalysis> analyzeFoodFull(
    List<int> imageBytes, {
    LocalFood? storedDish,
  }) {
    fullStoredDish = storedDish;
    return onAnalyzeFull!(imageBytes);
  }

  @override
  Future<FoodAnalysis> analyzeFoodByName(
    List<int> imageBytes,
    String name, {
    LocalFood? storedDish,
  }) {
    byNameStoredDish = storedDish;
    return onAnalyzeByName!(imageBytes, name);
  }

  @override
  Future<({bool isTypo, String correctedName})> checkTypedNameSpelling({
    required String typedName,
    required String observedFood,
  }) async {
    final Future<({bool isTypo, String correctedName})> Function(
      String typedName,
      String observedFood,
    )?
    callback = onSpellCheck;
    if (callback != null) return callback(typedName, observedFood);
    // Default: correctly spelled, so only tests that opt in see a typo.
    return (isTypo: false, correctedName: '');
  }

  @override
  Future<OriginVerification> verifyDishOrigin(String dishName) async {
    final OriginVerification Function(String)? callback = onVerifyOrigin;
    if (callback != null) return callback(dishName);
    // Default: 3/3 accept, so the Option-C gate passes unless a test opts in
    // to a reject/split via [onVerifyOrigin].
    return OriginVerification(
      dishName: dishName,
      verdict: OriginVerdict.accept,
      votesMalaysian: 3,
      directOrigin: (
        dishCase: OriginDishCase.malaysian,
        originCountry: 'Malaysia',
        originEthnicity: 'Malay',
        confidence: 0.9,
      ),
      adjudicate: (
        dishCase: OriginDishCase.malaysian,
        actualOriginCountry: 'Malaysia',
        distinguishingNotes: '',
      ),
      knownPattern: (
        isCommonlyMisattributed: false,
        correctOriginIfMisattributed: null,
        reasoning: '',
      ),
    );
  }
}

/// Fake catalogue repository - replaces Supabase's `getFoods` lookup with a
/// controllable in-memory catalogue list, and records `insertFood` calls.
class _FakeFoodKnowledgeRepository extends FoodKnowledgeRepository {
  List<LocalFood> catalogue = const <LocalFood>[];
  final List<LocalFood> inserted = <LocalFood>[];

  /// `local_food_image` links recorded by [addFoodImage].
  final List<({int localFoodId, String imageName})> images =
      <({int localFoodId, String imageName})>[];

  /// Curated `food_dietary_restriction` links per food id - empty by default,
  /// so tests that do not care see no dietary tags.
  Map<int, List<DietaryRestriction>> foodRestrictionLinks =
      const <int, List<DietaryRestriction>>{};

  @override
  Future<List<LocalFood>> getFoods() async => catalogue;

  @override
  Future<LocalFood?> insertFood(LocalFood food) async {
    inserted.add(food);
    // The real insert returns the row with its assigned identity id - a
    // plain increment keeps that contract for the tests that assert on the
    // id (e.g. the attached food-image link).
    return food.copyWith(id: 100 + inserted.length);
  }

  @override
  Future<void> addFoodImage({
    required int localFoodId,
    required String imageName,
  }) async {
    images.add((localFoodId: localFoodId, imageName: imageName));
  }

  /// Not an override - `FoodKnowledgeRepository` has no such method (the
  /// facade routes it to the dietary-restriction repository), but the fake
  /// exposes the stubbed links so [FoodRecognitionLogic._dietaryTagsFor] can
  /// be exercised without a network call.
  Future<List<DietaryRestriction>> foodDietaryRestrictions(
    int localFoodId,
  ) async => foodRestrictionLinks[localFoodId] ?? const <DietaryRestriction>[];
}

class _FakeDiscoveryRepositoryFacade extends DiscoveryRepositoryFacade {
  _FakeDiscoveryRepositoryFacade(this.fakeRecognition);

  final RecognitionRepository fakeRecognition;

  @override
  RecognitionRepository get recognition => fakeRecognition;
}

class _FakeFoodRepositoryFacade extends FoodRepositoryFacade {
  _FakeFoodRepositoryFacade(this.fakeKnowledge);

  final _FakeFoodKnowledgeRepository fakeKnowledge;

  @override
  Future<List<LocalFood>> getFoods() => fakeKnowledge.getFoods();

  @override
  Future<LocalFood?> insertFood(LocalFood food) =>
      fakeKnowledge.insertFood(food);

  @override
  Future<void> addFoodImage({
    required int localFoodId,
    required String imageName,
  }) => fakeKnowledge.addFoodImage(
    localFoodId: localFoodId,
    imageName: imageName,
  );

  @override
  Future<({Map<String, int> tastes, Map<String, int> categories})>
  preferenceIdLookup() async =>
      (tastes: <String, int>{}, categories: <String, int>{});

  @override
  Future<List<DietaryRestriction>> dietaryRestrictions() async =>
      const <DietaryRestriction>[];

  @override
  Future<void> linkFoodPreferences(
    int localFoodId, {
    required List<int> tasteIds,
    int mainTasteId = 0,
    int? categoryId,
  }) async {}

  @override
  Future<void> linkFoodDietaryRestrictions(
    int localFoodId,
    List<int> restrictionIds,
  ) async {}

  @override
  Future<List<DietaryRestriction>> foodDietaryRestrictions(int localFoodId) =>
      fakeKnowledge.foodDietaryRestrictions(localFoodId);
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

/// A quick (phase-1) Gemini-style response, controllable per test.
FoodAnalysisResponse _quickResponse({
  String dish = 'Murtabak',
  bool isLocal = true,
  double confidence = 1.0,
  String foodStatus = 'detected',
  String foodImageStatus = 'complete',
  int foodCount = 1,
  List<FoodCandidate> candidates = const <FoodCandidate>[],
  String foodType = '',
  double priceMin = 0,
  double priceMax = 0,
}) => FoodAnalysisResponse(
  dish: dish,
  variant: '',
  description: '',
  origin: '',
  cookingStyle: '',
  mealType: '',
  foodCategory: 'Malay',
  foodType: foodType,
  isMalaysianLocalFood: isLocal,
  culturalBackground: '',
  priceMin: priceMin,
  priceMax: priceMax,
  foodStatus: foodStatus,
  foodImageStatus: foodImageStatus,
  confidence: confidence,
  foodCount: foodCount,
  candidates: candidates,
);

void main() {
  group('FoodRecognitionLogic.recognizeFood', () {
    late _FakeRecognitionRepository recognition;
    late _FakeFoodKnowledgeRepository knowledge;
    late FoodRecognitionLogic logic;

    setUp(() {
      recognition = _FakeRecognitionRepository();
      knowledge = _FakeFoodKnowledgeRepository();
      logic = _TestFoodRecognitionLogic(
        _FakeDiscoveryRepositoryFacade(recognition),
        _FakeFoodRepositoryFacade(knowledge),
      );
    });

    test('throws when no food is detected (A4)', () async {
      recognition.onIdentify = (_) async =>
          _quickResponse(foodStatus: 'not_detected');

      await expectLater(
        logic.recognizeFood(<int>[1]),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'toString',
            contains('No food detected'),
          ),
        ),
      );
    });

    test('throws when the image frame is incomplete (A18)', () async {
      recognition.onIdentify = (_) async =>
          _quickResponse(foodImageStatus: 'partially_captured');

      await expectLater(
        logic.recognizeFood(<int>[1]),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'toString',
            contains('not complete'),
          ),
        ),
      );
    });

    test('throws when more than one dish is in the frame', () async {
      recognition.onIdentify = (_) async => _quickResponse(foodCount: 2);

      await expectLater(
        logic.recognizeFood(<int>[1]),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'toString',
            contains('only one food'),
          ),
        ),
      );
    });

    test(
      'non-local food returns details but flags isLocalFood=false (A3)',
      () async {
        final full = _food('Roti Canai');
        recognition.onIdentify = (_) async => _quickResponse(isLocal: false);
        recognition.onAnalyzeFull = (List<int> _) async => (
          food: full,
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: false,
          confidence: 1.0,
          localConfidence: 0.8,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.isLocalFood, isFalse);
        expect(result.candidates.length, 1);
        expect(result.candidates.single.name, 'Roti Canai');
      },
    );

    test('a classic Western dish can never be local food, even when the '
        'model and the catalogue say it is (French Toast floor)', () async {
      // The quick call reads the photo as "French Toast" and returns its
      // (occasionally wrong) "local" flag - the catalogue even holds a row.
      final frenchToast = _food('French Toast');
      knowledge.catalogue = <LocalFood>[frenchToast];
      recognition.onIdentify = (_) async => _quickResponse(
        dish: 'French Toast',
        confidence: 0.95,
        foodType: 'Food',
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // Floored to false - the card must not offer to add it as a landmark.
      expect(result.isLocalFood, isFalse);
      expect(result.candidates.single.name, 'French Toast');
    });

    test('the floor also holds when the full analysis re-judges a classic '
        'Western dish as local', () async {
      recognition.onIdentify = (_) async => _quickResponse(isLocal: false);
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: _food('French Toast'),
        priceMin: 0.0,
        priceMax: 0.0,
        isLocal: true, // The model's (wrong) re-judgement.
        confidence: 0.9,
        localConfidence: 0.6,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 0.9,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.isLocalFood, isFalse);
    });

    test('a Malaysian snack (e.g. Tam Tam) is not-addable even when it matches '
        'the catalogue', () async {
      final tamtam = _food('Tam Tam');
      knowledge.catalogue = <LocalFood>[tamtam];
      // Quick call names it confidently AND flags it as a non-catalogue
      // dish type (packaged snack).
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Tam Tam', confidence: 0.95, foodType: 'none');

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // Malaysian (so isLocalFood stays true) but a snack/package - it
      // must NOT be addable.
      expect(result.isLocalFood, isTrue);
      expect(result.fitsCatalogueCategory, isFalse);
      expect(result.candidates.single.name, 'Tam Tam');
    });

    test('a beverage classified as "Beverage" stays addable', () async {
      final tehTarik = _food('Teh Tarik');
      knowledge.catalogue = <LocalFood>[tehTarik];
      recognition.onIdentify = (_) async => _quickResponse(
        dish: 'Teh Tarik',
        confidence: 0.95,
        foodType: 'Beverage',
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.isLocalFood, isTrue);
      expect(result.fitsCatalogueCategory, isTrue);
    });

    test("the quick call's suggested price range rides the catalogue fast "
        'path', () async {
      final tehTarik = _food('Teh Tarik');
      knowledge.catalogue = <LocalFood>[tehTarik];
      recognition.onIdentify = (_) async => _quickResponse(
        dish: 'Teh Tarik',
        confidence: 0.95,
        foodType: 'Beverage',
        priceMin: 1.5,
        priceMax: 3.0,
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // The fast path skips the full analysis, so without the quick call
      // carrying the range this would be 0/0 - the live gap that left most
      // landmark_item.price_min/price_max NULL.
      expect(result.priceMin, 1.5);
      expect(result.priceMax, 3.0);
    });

    test('quick says not-local but the full analysis says local is still addable '
        '(Ramly burger case)', () async {
      final burger = _food('Burger Malaysia');
      // The quick name-only call under-rates it (a "burger" sounds Western) ...
      recognition.onIdentify = (_) async => _quickResponse(isLocal: false);
      // ... but the full analysis re-judges it Malaysian - its word wins,
      // so the tourist can still add it as a landmark.
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: burger,
        priceMin: 3.0,
        priceMax: 10.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.isLocalFood, isTrue);
      expect(result.candidates.single.name, 'Burger Malaysia');
    });

    test('a low-confidence catalogue match is verified by the full analysis '
        '(never shown as certain)', () async {
      final murtabak = _food('Murtabak');
      knowledge.catalogue = <LocalFood>[murtabak];
      // Gemini is only 40% sure - even though the name IS in the catalogue,
      // the full analysis must re-judge the photo instead of shortcutting
      // straight to that record and presenting it as certain.
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Murtabak', confidence: 0.4);
      bool analyzeFullCalled = false;
      recognition.onAnalyzeFull = (List<int> _) async {
        analyzeFullCalled = true;
        return (
          food: _food('Murtabak (verified)'),
          priceMin: 3.0,
          priceMax: 9.0,
          isLocal: true,
          confidence: 0.95,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );
      };

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(analyzeFullCalled, isTrue);
      // The full analysis verified the dish, but the EXISTING curated row
      // (its data + id) still wins over Gemini's fresh copy - Gemini must
      // never overwrite `local_food` data.
      expect(result.candidates.single.name, 'Murtabak');
      expect(result.candidates.single.id, 1);
      expect(result.confidence, 0.95);
    });

    test('a full-analysis dish already in the catalogue keeps the curated row '
        '(Gemini never overwrites local_food data)', () async {
      final nasi = _food('Nasi Lemak');
      knowledge.catalogue = <LocalFood>[nasi];
      // Quick call does NOT resolve to the catalogue (so the full analysis
      // runs) ...
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Something Else', confidence: 0.9);
      // ... and the full analysis identifies a dish that IS already curated -
      // the existing row (authoritative data + id) must win over Gemini's
      // fresh copy.
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: _food('Nasi Lemak (Gemini)'),
        priceMin: 3.0,
        priceMax: 8.0,
        isLocal: true,
        confidence: 0.95,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // The curated row wins - name AND id (so the item links to it).
      expect(result.candidates.single.name, 'Nasi Lemak');
      expect(result.candidates.single.id, 1);
      // Photo-submission properties still come from the full analysis.
      expect(result.confidence, 0.95);
      expect(result.priceMin, 3.0);
      expect(result.priceMax, 8.0);
    });

    test('top-3 candidates are surfaced in Gemini confidence order', () async {
      final murtabak = _food('Murtabak');
      final roti = _food('Roti Canai');
      final nasi = _food('Nasi Lemak');
      knowledge.catalogue = <LocalFood>[murtabak, roti, nasi];
      recognition.onIdentify = (_) async => _quickResponse(
        candidates: <FoodCandidate>[
          FoodCandidate(dish: 'Murtabak', confidence: 0.9),
          FoodCandidate(dish: 'Roti Canai', confidence: 0.8),
          FoodCandidate(dish: 'Nasi Lemak', confidence: 0.7),
        ],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.isLocalFood, isTrue);
      expect(result.candidates.map((LocalFood f) => f.name), <String>[
        'Murtabak',
        'Roti Canai',
        'Nasi Lemak',
      ]);
    });

    test('caps the picker at 3 candidates', () async {
      final List<LocalFood> foods = <String>[
        'A',
        'B',
        'C',
        'D',
      ].map(_food).toList();
      knowledge.catalogue = foods;
      recognition.onIdentify = (_) async => _quickResponse(
        candidates: <FoodCandidate>[
          FoodCandidate(dish: 'A', confidence: 0.9),
          FoodCandidate(dish: 'B', confidence: 0.8),
          FoodCandidate(dish: 'C', confidence: 0.7),
          FoodCandidate(dish: 'D', confidence: 0.6),
        ],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.candidates.length, 3);
      expect(result.candidates.map((LocalFood f) => f.name), <String>[
        'A',
        'B',
        'C',
      ]);
    });

    test(
      'a candidate missing from the catalogue is still offered name-only',
      () async {
        final murtabak = _food('Murtabak');
        knowledge.catalogue = <LocalFood>[murtabak];
        recognition.onIdentify = (_) async => _quickResponse(
          candidates: <FoodCandidate>[
            FoodCandidate(dish: 'Murtabak', confidence: 0.9),
            FoodCandidate(dish: 'Some Foreign Dish', confidence: 0.8),
          ],
        );

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.candidates.length, 2);
        expect(result.candidates[0].name, 'Murtabak');
        expect(result.candidates[1].name, 'Some Foreign Dish');
        // Name-only placeholder - no catalogue details yet.
        expect(result.candidates[1].description, isEmpty);
      },
    );

    test(
      'low-confidence candidates (< 0.5) are dropped, single path wins',
      () async {
        final murtabak = _food('Murtabak');
        knowledge.catalogue = <LocalFood>[murtabak];
        recognition.onIdentify = (_) async => _quickResponse(
          dish: 'Murtabak',
          candidates: <FoodCandidate>[
            FoodCandidate(dish: 'Murtabak', confidence: 0.9),
            FoodCandidate(dish: 'Roti Canai', confidence: 0.4),
          ],
        );
        bool analyzeFullCalled = false;
        recognition.onAnalyzeFull = (List<int> _) async {
          analyzeFullCalled = true;
          return (
            food: _food('Murtabak'),
            priceMin: 0.0,
            priceMax: 0.0,
            isLocal: true,
            confidence: 1.0,
            localConfidence: 1.0,
            imageQuality: 'good',
            imageQualityIssues: const <String>[],
            nameMatchesPhoto: true,
            matchConfidence: 1.0,
            observedFood: '',
            foodType: 'Food',
            dietaryRestrictions: const <String>[],
          );
        };

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.candidates.length, 1);
        expect(result.candidates.single.name, 'Murtabak');
        // Resolved from the catalogue - no expensive full call needed.
        expect(analyzeFullCalled, isFalse);
      },
    );

    test(
      'confident single result in the catalogue skips the full call',
      () async {
        final murtabak = _food('Murtabak');
        knowledge.catalogue = <LocalFood>[murtabak];
        recognition.onIdentify = (_) async => _quickResponse(dish: 'Murtabak');
        bool analyzeFullCalled = false;
        recognition.onAnalyzeFull = (List<int> _) async {
          analyzeFullCalled = true;
          return (
            food: _food('X'),
            priceMin: 0.0,
            priceMax: 0.0,
            isLocal: true,
            confidence: 1.0,
            localConfidence: 1.0,
            imageQuality: 'good',
            imageQualityIssues: const <String>[],
            nameMatchesPhoto: true,
            matchConfidence: 1.0,
            observedFood: '',
            foodType: 'Food',
            dietaryRestrictions: const <String>[],
          );
        };

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.candidates.single.name, 'Murtabak');
        expect(analyzeFullCalled, isFalse);
      },
    );

    test(
      'confident single result NOT in the catalogue runs the full call',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        recognition.onIdentify = (_) async =>
            _quickResponse(dish: 'Unknown Dish');
        recognition.onAnalyzeFull = (List<int> _) async => (
          food: _food('Unknown Dish (full)'),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.candidates.single.name, 'Unknown Dish (full)');
      },
    );

    test('duplicate candidate names are deduplicated', () async {
      final murtabak = _food('Murtabak');
      final roti = _food('Roti Canai');
      knowledge.catalogue = <LocalFood>[murtabak, roti];
      recognition.onIdentify = (_) async => _quickResponse(
        candidates: <FoodCandidate>[
          FoodCandidate(dish: 'Murtabak', confidence: 0.9),
          FoodCandidate(dish: 'Murtabak', confidence: 0.8),
          FoodCandidate(dish: 'Roti Canai', confidence: 0.7),
        ],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.candidates.length, 2);
      expect(result.candidates.map((LocalFood f) => f.name), <String>[
        'Murtabak',
        'Roti Canai',
      ]);
    });

    test('a confident catalogue hit reads tags from the curated row\'s own '
        'food_dietary_restriction links (fast path)', () async {
      final bubur = _food('Bubur Cha Cha');
      knowledge.catalogue = <LocalFood>[bubur];
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Bubur Cha Cha', confidence: 0.98);
      // The curated catalogue links Bubur Cha Cha ONLY to No Coconut.
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        bubur.id: <DietaryRestriction>[
          const DietaryRestriction(id: 19, name: 'No Coconut'),
        ],
      };
      bool analyzeFullCalled = false;
      recognition.onAnalyzeFull = (List<int> _) async {
        analyzeFullCalled = true;
        return (
          food: _food('Bubur Cha Cha'),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>['No Gluten', 'No Egg'],
        );
      };

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // Fast path: full analysis never ran, so the only tags possible are
      // the curated links - and they must be present (the warning relies on
      // them).
      expect(analyzeFullCalled, isFalse);
      expect(result.candidates.single.id, bubur.id);
      expect(result.dietaryRestrictions, <String>['No Coconut']);
    });

    test('a curated dish matched by the full analysis keeps the observed tags '
        '(the variant\'s own facts)', () async {
      final bubur = _food('Bubur Cha Cha');
      knowledge.catalogue = <LocalFood>[bubur];
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        bubur.id: <DietaryRestriction>[
          const DietaryRestriction(id: 19, name: 'No Coconut'),
        ],
      };
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Bubur Cha Cha', confidence: 0.4);
      // The full analysis judges it a curated dish and OBSERVED these tags
      // on this very photo - they describe the variant and ride the item.
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: _food('Bubur Cha Cha (Gemini)'),
        priceMin: 2.0,
        priceMax: 5.0,
        isLocal: true,
        confidence: 0.9,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[
          'No Coconut',
          'No Gluten',
          'No Egg',
        ],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // The dish resolves to the catalogue row (its details/id win), while
      // the FRESH observation's tags are what the item records - hybrid
      // storage, so a variant's own facts are never lost.
      expect(result.candidates.single.id, bubur.id);
      expect(result.dietaryRestrictions, <String>[
        'No Coconut',
        'No Gluten',
        'No Egg',
      ]);
    });

    test('a curated dish whose analysis observed no tags falls back to its '
        'own food_dietary_restriction links', () async {
      final bubur = _food('Bubur Cha Cha');
      knowledge.catalogue = <LocalFood>[bubur];
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        bubur.id: <DietaryRestriction>[
          const DietaryRestriction(id: 19, name: 'No Coconut'),
        ],
      };
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Bubur Cha Cha', confidence: 0.4);
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: _food('Bubur Cha Cha (Gemini)'),
        priceMin: 2.0,
        priceMax: 5.0,
        isLocal: true,
        confidence: 0.9,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // Nothing observed => the curated row's own links are the fallback.
      expect(result.candidates.single.id, bubur.id);
      expect(result.dietaryRestrictions, <String>['No Coconut']);
    });

    test('a recognised variant ("Cendol Jagung") stores the dictionary dish '
        'with the variant name + observed ingredients', () async {
      final cendol = _food('Cendol').copyWith(
        id: 375,
        ingredients: 'Pandan jelly, coconut milk, palm sugar, shaved ice',
      );
      knowledge.catalogue = <LocalFood>[cendol];
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Cendol Jagung', confidence: 0.4);
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: LocalFood(
          id: 0, // Gemini's unsaved copy - the curated row beats it.
          name: 'Cendol Jagung',
          description: 'Cendol topped with sweet corn',
          origin: 'Malaysia',
          culturalBackground: '',
          ingredients: 'Pandan jelly, coconut milk, gula Melaka, sweet corn',
          category: 'Dessert',
          cookingStyle: 'Chilling',
          mealType: 'Dessert',
          foodType: 'Dessert',
        ),
        priceMin: 3.0,
        priceMax: 8.0,
        isLocal: true,
        confidence: 0.9,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Dessert',
        dietaryRestrictions: const <String>['Contains Coconut'],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // The dictionary row keeps the dish's identity (id + name)...
      expect(result.candidates.single.id, cendol.id);
      expect(result.candidates.single.name, 'Cendol');
      // ...while the ITEM records the dish AS SHOWN: the variant's own
      // description + category (the row was sent as the stored record and the
      // analysis changed what the variant changes) ...
      expect(
        result.candidates.single.description,
        'Cendol topped with sweet corn',
      );
      expect(result.candidates.single.category, 'Dessert');
      // ...the VARIANT name is recorded for `landmark_item.variant`...
      expect(result.variant, 'Cendol Jagung');
      // ...and the item INHERITS the dictionary's ingredients and gains the
      // observation's extras ("gula Melaka", "sweet corn") - what makes it
      // that variant - with the entries both sides name only once.
      expect(
        result.candidates.single.ingredients,
        'Pandan jelly, coconut milk, palm sugar, shaved ice, gula Melaka, '
        'sweet corn',
      );
    });

    test('a high-confidence variant still gets the photo analysed - the '
        'dictionary row cannot describe it', () async {
      final cendol = _food('Cendol').copyWith(
        id: 375,
        ingredients: 'Pandan jelly, coconut milk, palm sugar',
      );
      knowledge.catalogue = <LocalFood>[cendol];
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        cendol.id: <DietaryRestriction>[
          const DietaryRestriction(id: 5, name: 'Contains Coconut'),
        ],
      };
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Cendol Jagung', confidence: 0.95);
      bool analyzeFullCalled = false;
      recognition.onAnalyzeFull = (List<int> _) async {
        analyzeFullCalled = true;
        return (
          food: LocalFood(
            id: 0, // Gemini's unsaved copy - the curated row beats it.
            name: 'Cendol Jagung',
            description: 'Cendol topped with sweet corn',
            origin: 'Malaysia',
            culturalBackground: '',
            ingredients: 'Pandan jelly, coconut milk, gula Melaka, sweet corn',
            category: 'Dessert',
            cookingStyle: 'Chilled',
            mealType: 'Dessert',
            foodType: 'Dessert',
          ),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: true,
          confidence: 0.95,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Dessert',
          dietaryRestrictions: const <String>['Contains Coconut'],
        );
      };

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // The row cannot describe a variant it does not know, so the photo's
      // own reading is fetched even though the name was read confidently.
      expect(analyzeFullCalled, isTrue);
      expect(result.candidates.single.id, cendol.id);
      expect(result.variant, 'Cendol Jagung');
      // The dictionary's facts PLUS the variant's own observed extras.
      expect(
        result.candidates.single.ingredients,
        'Pandan jelly, coconut milk, palm sugar, gula Melaka, sweet corn',
      );
      // Both dietary sources apply, deduplicated.
      expect(result.dietaryRestrictions, <String>['Contains Coconut']);
    });

    test('a pork VARIANT of a curated dish carries the pork the photo shows '
        '(Siew Yoke Nasi Lemak)', () async {
      final nasiLemak = _food('Nasi Lemak').copyWith(
        id: 19,
        ingredients: 'Rice, coconut milk, anchovies, peanuts, egg',
      );
      knowledge.catalogue = <LocalFood>[nasiLemak];
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        nasiLemak.id: <DietaryRestriction>[
          const DietaryRestriction(id: 11, name: 'No Peanuts'),
        ],
      };
      // The quick call reads the photo as the PORK variant - a name that only
      // EXTENDS the curated row.
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Siew Yoke Nasi Lemak', confidence: 0.98);
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: LocalFood(
          id: 0,
          name: 'Siew Yoke Nasi Lemak',
          description: 'Nasi lemak served with roast pork',
          origin: 'Malaysia',
          culturalBackground: 'Chinese coffee-shop take on nasi lemak.',
          ingredients:
              'Rice, coconut milk, anchovies, peanuts, siew yoke (roast pork)',
          category: 'Chinese',
          cookingStyle: 'Braised',
          mealType: 'All-Day Dining',
          foodType: 'Food',
        ),
        priceMin: 9.0,
        priceMax: 14.0,
        isLocal: true,
        confidence: 0.95,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>['No Pork'],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // The stored catalogue record was SENT with the call ...
      expect(recognition.fullStoredDish?.name, 'Nasi Lemak');
      // ... the curated row still IS the dish (its id links the item) ...
      expect(result.candidates.single.id, nasiLemak.id);
      expect(result.candidates.single.name, 'Nasi Lemak');
      expect(result.variant, 'Siew Yoke Nasi Lemak');
      // ... the item records the row ADAPTED to the variant the photo showed
      // (the model's description/category/culture for the dish as shown) ...
      expect(
        result.candidates.single.description,
        'Nasi lemak served with roast pork',
      );
      expect(result.candidates.single.category, 'Chinese');
      expect(
        result.candidates.single.culturalBackground,
        'Chinese coffee-shop take on nasi lemak.',
      );
      // ... and the pork the photo showed is IN the ingredients now ...
      expect(result.candidates.single.ingredients, contains('roast pork'));
      // ... so a tourist avoiding pork is warned, without losing the base
      // dish's own peanut warning.
      expect(result.dietaryRestrictions, <String>['No Peanuts', 'No Pork']);
    });

    test('an analysis that found nothing to change leaves the stored row\'s '
        'own text ("use local food if it is really valid")', () async {
      final nasiLemak = _food('Nasi Lemak').copyWith(
        id: 19,
        description: 'Fragrant rice cooked in coconut milk and pandan.',
        culturalBackground: 'Part of Malaysia\'s Malay culinary tradition.',
        ingredients: 'Rice, coconut milk, anchovies, peanuts, egg',
      );
      knowledge.catalogue = <LocalFood>[nasiLemak];
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Nasi Lemak Ayam', confidence: 0.98);
      // The model judged the stored text still valid for this variant: it
      // echoed nothing, only naming the ingredient the variant adds.
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: LocalFood(
          id: 0,
          name: 'Nasi Lemak Ayam',
          description: '',
          origin: '',
          culturalBackground: '',
          ingredients: 'Rice, coconut milk, anchovies, peanuts, fried chicken',
          category: '',
          cookingStyle: '',
          mealType: '',
          foodType: 'Food',
        ),
        priceMin: 0.0,
        priceMax: 0.0,
        isLocal: true,
        confidence: 0.95,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(recognition.fullStoredDish?.name, 'Nasi Lemak');
      expect(result.variant, 'Nasi Lemak Ayam');
      // Nothing was changed by the variant, so the STORED text stands ...
      expect(
        result.candidates.single.description,
        'Fragrant rice cooked in coconut milk and pandan.',
      );
      expect(result.candidates.single.category, 'Malay');
      expect(
        result.candidates.single.culturalBackground,
        'Part of Malaysia\'s Malay culinary tradition.',
      );
      // ... while the observed ingredient still joins the stored list.
      expect(result.candidates.single.ingredients, contains('fried chicken'));
    });

    test('an analysis that echoes the stored dish name still keeps the photo\'s '
        'variant + adapted fields', () async {
      final nasiLemak = _food('Nasi Lemak').copyWith(
        id: 19,
        description: 'Fragrant rice cooked in coconut milk and pandan.',
        ingredients: 'Rice, coconut milk, anchovies, peanuts, egg',
      );
      knowledge.catalogue = <LocalFood>[nasiLemak];
      // The quick call names the PORK variant ...
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Siew Yoke Nasi Lemak', confidence: 0.98);
      // ... while the analysis (SENT the stored record) echoes the plain
      // dish back - as the prompt lets it do while the record still holds.
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: LocalFood(
          id: 0,
          name: 'Nasi Lemak',
          description:
              'Fragrant rice cooked in coconut milk and pandan, served '
              'with siew yoke.',
          origin: 'Malaysia',
          culturalBackground: 'Chinese coffee-shop take on nasi lemak.',
          ingredients:
              'Rice, coconut milk, anchovies, peanuts, siew yoke (roast pork)',
          category: 'Chinese',
          cookingStyle: 'Braised',
          mealType: 'All-Day Dining',
          foodType: 'Food',
        ),
        priceMin: 9.0,
        priceMax: 14.0,
        isLocal: true,
        confidence: 0.95,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>['No Pork'],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(recognition.fullStoredDish?.name, 'Nasi Lemak');
      // The same-dish name the analysis echoed does NOT lose what the photo
      // showed (the quick call's variant) ...
      expect(result.candidates.single.id, nasiLemak.id);
      expect(result.variant, 'Siew Yoke Nasi Lemak');
      // ... so the item still takes the row ADAPTED to the variant: the
      // pork in the ingredients and the category moved OFF the Malay base
      // dish, which is exactly what "the category did not change" reported.
      expect(result.candidates.single.ingredients, contains('roast pork'));
      expect(result.candidates.single.category, 'Chinese');
      expect(result.candidates.single.description, contains('siew yoke'));
    });

    test('a match on the dictionary name records no variant', () async {
      knowledge.catalogue = <LocalFood>[_food('Cendol').copyWith(id: 375)];
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Cendol', confidence: 0.95);

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(result.variant, isEmpty);
    });

    test(
      'a curated synonym spelling records NO variant (same dish, not a variant)',
      () async {
        final cendol = _food(
          'Cendol',
        ).copyWith(id: 375, synonyms: <String>['cendol gula Melaka']);
        knowledge.catalogue = <LocalFood>[cendol];
        recognition.onIdentify = (_) async =>
            _quickResponse(dish: 'Cendol Gula Melaka', confidence: 0.95);

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        // The synonym IS the dish - the item simply uses the curated row.
        expect(result.candidates.single.id, 375);
        expect(result.variant, isEmpty);
      },
    );

    test(
      "an extension that only adds the dish's own synonym records NO variant "
      '("Ais Kacang (ABC)")',
      () async {
        final aisKacang = _food('Ais Kacang').copyWith(
          id: 250,
          synonyms: <String>['ABC', 'air batu campur', 'ice kacang'],
        );
        knowledge.catalogue = <LocalFood>[aisKacang];
        recognition.onIdentify = (_) async =>
            _quickResponse(dish: 'Ais Kacang (ABC)', confidence: 0.95);

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        // 'ABC' IS the dish (a curated synonym) - the parenthesised spelling
        // is not a variant, so the item uses the curated row alone and the
        // same dish can never end up listed twice on the form.
        expect(result.candidates.single.id, 250);
        expect(result.variant, isEmpty);
      },
    );

    test(
      'a brand-new dish (no curated row) keeps Gemini\'s dietary tags',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        recognition.onIdentify = (_) async =>
            _quickResponse(dish: 'Some New Dessert', confidence: 0.4);
        recognition.onAnalyzeFull = (List<int> _) async => (
          food: LocalFood(
            id: 0, // Not yet saved - a brand-new Gemini dish.
            name: 'Some New Dessert',
            description: 'Description',
            origin: 'Malaysia',
            culturalBackground: '',
            ingredients: '',
            category: 'Malay',
            cookingStyle: 'Frying',
            mealType: 'Dessert',
            foodType: 'Dessert',
          ),
          priceMin: 2.0,
          priceMax: 5.0,
          isLocal: true,
          confidence: 0.9,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Dessert',
          dietaryRestrictions: const <String>['No Coconut'],
        );

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.candidates.single.id, 0);
        expect(result.dietaryRestrictions, <String>['No Coconut']);
      },
    );

    test('a Gemini-reported alias resolves a non-canonical dish name to its '
        'curated row instead of creating a duplicate (bubur ca ca)', () async {
      final canonical = _food('Bubur Cha Cha');
      knowledge.catalogue = <LocalFood>[canonical];
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'bubur ca ca', confidence: 0.4);
      recognition.onAnalyzeFull = (List<int> _) async => (
        food: _food('bubur ca ca').copyWith(
          id: 0, // A fresh Gemini copy - not yet a catalogue row.
          aliases: <String>['Bubur Cha Cha', 'Bubur Chacha'],
        ),
        priceMin: 3.5,
        priceMax: 6.0,
        isLocal: true,
        confidence: 0.9,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 1.0,
        observedFood: '',
        foodType: 'Dessert',
        dietaryRestrictions: const <String>[],
      );

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      // Curated wins via the alias - the SAME row the data migration makes
      // canonical, never an id-0 copy that would become a second row.
      expect(result.candidates.single.id, canonical.id);
      expect(result.candidates.single.name, 'Bubur Cha Cha');
    });

    test(
      'an alias claimed by several catalogue rows is ambiguous and ignored',
      () async {
        // The live catalogue has this exact collision: 'Bubur Pulut Hitam'
        // is Bee Koh Moy's synonym AND another row's food_name.
        final beeKohMoy = _food(
          'Bee Koh Moy',
        ).copyWith(id: 362, synonyms: <String>['Bubur Pulut Hitam']);
        final pulutHitam = _food('Bubur Pulut Hitam').copyWith(id: 237);
        knowledge.catalogue = <LocalFood>[beeKohMoy, pulutHitam];
        recognition.onIdentify = (_) async =>
            _quickResponse(dish: 'unlisted spelling', confidence: 0.4);
        recognition.onAnalyzeFull = (List<int> _) async => (
          food: _food(
            'unlisted spelling',
          ).copyWith(id: 0, aliases: <String>['Bubur Pulut Hitam']),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: true,
          confidence: 0.9,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Dessert',
          dietaryRestrictions: const <String>[],
        );

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        // Ambiguous aliases must never pick an arbitrary winner.
        expect(result.candidates.single.id, 0);
        expect(result.candidates.single.name, 'unlisted spelling');
      },
    );
  });

  group('FoodRecognitionLogic.resolveByName (manual entry)', () {
    late _FakeRecognitionRepository recognition;
    late _FakeFoodKnowledgeRepository knowledge;
    late FoodRecognitionLogic logic;

    setUp(() {
      recognition = _FakeRecognitionRepository();
      knowledge = _FakeFoodKnowledgeRepository();
      logic = _TestFoodRecognitionLogic(
        _FakeDiscoveryRepositoryFacade(recognition),
        _FakeFoodRepositoryFacade(knowledge),
      );
    });

    test('always verifies the typed name against the photo, then prefers the '
        'catalogue for details once verified', () async {
      final murtabak = _food('Murtabak');
      knowledge.catalogue = <LocalFood>[murtabak];
      bool analyzeByNameCalled = false;
      // Gemini confirms the photo shows the typed name...
      recognition.onAnalyzeByName = (List<int> _, String name) async {
        analyzeByNameCalled = true;
        return (
          food: _food('Murtabak (Gemini)'),
          priceMin: 1.5,
          priceMax: 6.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 0.9,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );
      };

      final result = await logic.resolveByName(<int>[1], 'Murtabak');

      // The verification call ALWAYS happens - a catalogue hit is a details
      // optimisation, never a substitute for checking the photo.
      expect(analyzeByNameCalled, isTrue);
      expect(result.nameMatchesPhoto, isTrue);
      expect(result.isLocalFood, isTrue);
      // Once verified, the curated catalogue row's details are preferred...
      expect(result.food.name, 'Murtabak');
      // ...and Gemini's suggested range for the verified typed dish rides
      // along, so the form can show it under the price field.
      expect(result.priceMin, 1.5);
      expect(result.priceMax, 6.0);
    });

    test(
      'typing a classic Western dish stays non-local even when verified',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food(name),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 0.95,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );

        final result = await logic.resolveByName(<int>[1], 'French Toast');

        expect(result.nameMatchesPhoto, isTrue);
        expect(result.isLocalFood, isFalse);
      },
    );

    test(
      'sends the typed name + image to Gemini and returns that one dish',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        // The repository names the result exactly what was typed - the fake
        // mirrors that by returning a food named after [name].
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food(name),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );

        final result = await logic.resolveByName(<int>[1], '  Murtabak ');

        // Name trimmed, and the returned food is exactly the typed dish.
        expect(result.food.name, 'Murtabak');
        expect(result.nameMatchesPhoto, isTrue);
      },
    );

    test(
      'reports a mismatch (and the observed food) instead of agreeing',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        // Photograph a pizza, type "Nasi Lemak": Gemini says the photo does
        // NOT show nasi lemak - it sees a pepperoni pizza.
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food('Nasi Lemak'),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: false,
          confidence: 0.95,
          localConfidence: 0.9,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: false,
          matchConfidence: 0.9,
          observedFood: 'Pepperoni Pizza',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );

        final result = await logic.resolveByName(<int>[1], 'Nasi Lemak');

        expect(result.nameMatchesPhoto, isFalse);
        expect(result.matchConfidence, 0.9);
        expect(result.observedFood, 'Pepperoni Pizza');
        // A mismatched typed name must not pass the local-food gate.
        expect(result.isLocalFood, isFalse);
        // The typed name is kept (warn-and-allow) so the UI can warn.
        expect(result.food.name, 'Nasi Lemak');
      },
    );

    test('a mismatched typed name with no curated row carries a name-only '
        'entry - no details borrowed from the observed dish', () async {
      knowledge.catalogue = const <LocalFood>[];
      // The photo shows a Ramly burger, but the tourist insists it is "Char
      // Siew". Gemini flags the mismatch and reports what it actually sees.
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: _food(name), // the repo used to force the typed name onto this
        priceMin: 3.0,
        priceMax: 9.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: false,
        matchConfidence: 0.95,
        observedFood: 'Ramly Burger',
        foodType: 'Food',
        dietaryRestrictions: const <String>['No Pork'],
      );

      final result = await logic.resolveByName(<int>[1], 'Char Siew');

      // The mismatch is still reported so the UI can warn ...
      expect(result.nameMatchesPhoto, isFalse);
      expect(result.observedFood, 'Ramly Burger');
      // ... but the carried food is the TYPED dish, name-only - it must NOT
      // be a "Char Siew" name riding on the Ramly burger's details.
      expect(result.food.name, 'Char Siew');
      expect(result.food.description, isEmpty);
      expect(result.food.id, 0);
      // No observed-dish dietary or price leaks onto the typed dish either.
      expect(result.dietaryRestrictions, isEmpty);
      expect(result.priceMin, 0.0);
      expect(result.priceMax, 0.0);
    });

    test('spelling variants count as a match, not a mismatch', () async {
      knowledge.catalogue = const <LocalFood>[];
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: _food('Char Kway Teow'),
        priceMin: 0.0,
        priceMax: 0.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true, // "char kuey teow" == "char kway teow"
        matchConfidence: 0.85,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final result = await logic.resolveByName(<int>[1], 'char kuey teow');

      expect(result.nameMatchesPhoto, isTrue);
      expect(result.food.name, 'Char Kway Teow');
    });

    test('a mismatched typed name that is curated still carries the curated '
        'row once the tourist confirms it', () async {
      final murtabak = _food('Murtabak');
      knowledge.catalogue = <LocalFood>[murtabak];
      // Photo shows a pizza, tourist types "Murtabak": Gemini flags the
      // mismatch, but the typed dish IS already curated.
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: _food('Murtabak (Gemini)'),
        priceMin: 1.5,
        priceMax: 6.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: false,
        matchConfidence: 0.9,
        observedFood: 'Pepperoni Pizza',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final result = await logic.resolveByName(<int>[1], 'Murtabak');

      // The mismatch is still reported so the UI can warn ...
      expect(result.nameMatchesPhoto, isFalse);
      expect(result.observedFood, 'Pepperoni Pizza');
      // ... but the carried food for the typed dish is the curated row -
      // Gemini must never overwrite existing `local_food` data.
      expect(result.food.name, 'Murtabak');
      expect(result.food.id, 1);
      expect(result.priceMin, 0.0);
    });

    test(
      'a curated typed dish keeps the observation\'s dietary tags',
      () async {
        final murtabak = _food('Murtabak');
        knowledge.catalogue = <LocalFood>[murtabak];
        knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
          murtabak.id: <DietaryRestriction>[
            const DietaryRestriction(id: 1, name: 'No Pork'),
          ],
        };
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food('Murtabak (Gemini)'),
          priceMin: 3.0,
          priceMax: 8.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          // The photo was verified as showing the typed dish, so the observed
          // tags describe THIS dish and ride the item.
          dietaryRestrictions: const <String>['No Pork', 'No Gluten'],
        );

        final result = await logic.resolveByName(<int>[1], 'Murtabak');

        expect(result.food.id, murtabak.id);
        expect(result.dietaryRestrictions, <String>['No Pork', 'No Gluten']);
      },
    );

    test(
      'a typed variant name is recorded while the curated dish links',
      () async {
        final cendol = _food('Cendol').copyWith(id: 375);
        knowledge.catalogue = <LocalFood>[cendol];
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food('Cendol Jagung').copyWith(
            id: 0,
            ingredients: 'Pandan jelly, coconut milk, gula Melaka, sweet corn',
          ),
          priceMin: 3.0,
          priceMax: 8.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 0.9,
          observedFood: '',
          foodType: 'Dessert',
          dietaryRestrictions: const <String>[],
        );

        final result = await logic.resolveByName(<int>[1], 'Cendol Jagung');

        // The typed variant resolves to the curated 'Cendol' row...
        expect(result.food.id, cendol.id);
        expect(result.food.name, 'Cendol');
        // ...while the item records what the tourist actually typed.
        expect(result.variant, 'Cendol Jagung');
      },
    );

    test('a typed variant keeps BOTH the dish\'s own links and the variant\'s '
        'observed tag (Siew Yoke Nasi Lemak)', () async {
      final nasiLemak = _food('Nasi Lemak').copyWith(
        id: 19,
        ingredients: 'Rice, coconut milk, anchovies, peanuts, egg',
      );
      knowledge.catalogue = <LocalFood>[nasiLemak];
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        nasiLemak.id: <DietaryRestriction>[
          const DietaryRestriction(id: 11, name: 'No Peanuts'),
        ],
      };
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: LocalFood(
          id: 0,
          name: 'Siew Yoke Nasi Lemak',
          description: 'Nasi lemak served with roast pork',
          origin: 'Malaysia',
          culturalBackground: '',
          ingredients:
              'Rice, coconut milk, anchovies, peanuts, siew yoke (roast pork)',
          category: 'Chinese',
          cookingStyle: 'Braised',
          mealType: 'All-Day Dining',
          foodType: 'Food',
        ),
        priceMin: 9.0,
        priceMax: 14.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 0.95,
        observedFood: '',
        foodType: 'Food',
        dietaryRestrictions: const <String>['No Pork'],
      );

      final result = await logic.resolveByName(<int>[
        1,
      ], 'Siew Yoke Nasi Lemak');

      // The row the typed name matched was SENT as the stored record ...
      expect(recognition.byNameStoredDish?.name, 'Nasi Lemak');
      // ... the curated row IS the dish (its id links the item) ...
      expect(result.food.id, nasiLemak.id);
      expect(result.food.name, 'Nasi Lemak');
      expect(result.variant, 'Siew Yoke Nasi Lemak');
      // ... the item takes the row ADAPTED to the typed variant ...
      expect(result.food.description, 'Nasi lemak served with roast pork');
      // ... with the variant's own pork added to the ingredients ...
      expect(result.food.ingredients, contains('roast pork'));
      // ... and BOTH dietary sources: the row's peanuts + the pork.
      expect(result.dietaryRestrictions, <String>['No Peanuts', 'No Pork']);
    });

    test(
      'a word-order spelling links to its own row and records no variant',
      () async {
        final cendol = _food('Cendol').copyWith(id: 375);
        final nyonya = _food('Nyonya Cendol').copyWith(id: 58);
        knowledge.catalogue = <LocalFood>[cendol, nyonya];
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food('cendol nyonya').copyWith(id: 0),
          priceMin: 3.0,
          priceMax: 6.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 0.9,
          observedFood: '',
          foodType: 'Dessert',
          dietaryRestrictions: const <String>[],
        );

        final result = await logic.resolveByName(<int>[1], 'cendol nyonya');

        // "cendol nyonya" is "Nyonya Cendol" - it must link to THAT row,
        // never to the plain 'Cendol' prefix - and being the same dish it
        // records no variant.
        expect(result.food.id, 58);
        expect(result.variant, isEmpty);
      },
    );

    test('a verified typed alias resolves to the curated row via Gemini '
        'aliases (bubur ca ca)', () async {
      final canonical = _food('Bubur Cha Cha');
      knowledge.catalogue = <LocalFood>[canonical];
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: _food(
          'bubur ca ca',
        ).copyWith(id: 0, aliases: <String>['Bubur Cha Cha', 'Bubur Chacha']),
        priceMin: 3.5,
        priceMax: 6.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 0.9,
        observedFood: '',
        foodType: 'Dessert',
        dietaryRestrictions: const <String>[],
      );

      final result = await logic.resolveByName(<int>[1], 'bubur ca ca');

      // Gemini confirms the photo shows "bubur ca ca" AND reports it is also
      // known as "Bubur Cha Cha" - the curated row wins, so the item links to
      // the existing local_food instead of creating a duplicate.
      expect(result.nameMatchesPhoto, isTrue);
      expect(result.food.id, canonical.id);
      expect(result.food.name, 'Bubur Cha Cha');
    });

    test('Gemini aliases are ignored on a mismatch (they describe the '
        'observed dish, not what was typed)', () async {
      // The photo shows pizza, but Gemini happens to list "Bubur Cha Cha" as
      // an alias of what it saw - it must not relabel the typed dish.
      knowledge.catalogue = <LocalFood>[_food('Bubur Cha Cha')];
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: _food(name).copyWith(id: 0, aliases: <String>['Bubur Cha Cha']),
        priceMin: 0.0,
        priceMax: 0.0,
        isLocal: false,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: false,
        matchConfidence: 0.9,
        observedFood: 'Pepperoni Pizza',
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );

      final result = await logic.resolveByName(<int>[1], 'bubur ca ca');

      expect(result.nameMatchesPhoto, isFalse);
      // The typed dish stays name-only - never silently relabelled as the
      // curated dish the OBSERVED food's aliases happen to mention.
      expect(result.food.name, 'bubur ca ca');
      expect(result.food.id, 0);
    });
  });

  group('FoodRecognitionLogic.resolveByName (spelling gate)', () {
    late _FakeRecognitionRepository recognition;
    late _FakeFoodKnowledgeRepository knowledge;
    late FoodRecognitionLogic logic;

    setUp(() {
      recognition = _FakeRecognitionRepository();
      knowledge = _FakeFoodKnowledgeRepository();
      logic = _TestFoodRecognitionLogic(
        _FakeDiscoveryRepositoryFacade(recognition),
        _FakeFoodRepositoryFacade(knowledge),
      );
    });

    /// A by-name analysis for a photo that MATCHED the typed dish, with
    /// [observedFood] naming what Gemini saw.
    void matchedAnalysis(String observedFood) {
      recognition.onAnalyzeByName = (List<int> _, String name) async => (
        food: _food(name),
        priceMin: 0.0,
        priceMax: 0.0,
        isLocal: true,
        confidence: 1.0,
        localConfidence: 1.0,
        imageQuality: 'good',
        imageQualityIssues: const <String>[],
        nameMatchesPhoto: true,
        matchConfidence: 0.9,
        observedFood: observedFood,
        foodType: 'Food',
        dietaryRestrictions: const <String>[],
      );
    }

    test(
      'a misspelled typed name is replaced by its corrected spelling',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        matchedAnalysis('Pork Belly');
        String? askedTyped;
        String? askedObserved;
        recognition.onSpellCheck =
            (String typedName, String observedFood) async {
              askedTyped = typedName;
              askedObserved = observedFood;
              return (isTypo: true, correctedName: 'Pork Belly');
            };

        final result = await logic.resolveByName(<int>[1], 'prok belly');

        // The gate compared exactly what was typed against what the photo
        // showed...
        expect(askedTyped, 'prok belly');
        expect(askedObserved, 'Pork Belly');
        // ...and the typo never becomes the dish: the corrected spelling does.
        expect(result.typedNameIsTypo, isTrue);
        expect(result.correctedName, 'Pork Belly');
        expect(result.food.name, 'Pork Belly');
        expect(result.nameMatchesPhoto, isTrue);
      },
    );

    test('a variant is never shortened to its base dish by the gate '
        '(nasi lemak with pork stays a variant)', () async {
      final LocalFood nasiLemak = _food('Nasi Lemak').copyWith(id: 19);
      knowledge.catalogue = <LocalFood>[nasiLemak];
      matchedAnalysis('Nasi Lemak');
      // A model that "corrects" the variant to the plain dish must not be
      // followed - losing words is not a spelling fix.
      recognition.onSpellCheck = (String _, String _) async =>
          (isTypo: true, correctedName: 'Nasi Lemak');

      final result = await logic.resolveByName(<int>[
        1,
      ], 'Nasi Lemak with Pork');

      expect(result.typedNameIsTypo, isFalse);
      expect(result.correctedName, '');
      // The curated row IS the dish (its id links the item) ...
      expect(result.food.id, nasiLemak.id);
      expect(result.food.name, 'Nasi Lemak');
      // ... and the pork the tourist named is recorded as its VARIANT - the
      // plain dish would record none.
      expect(result.variant, 'Nasi Lemak with Pork');
    });

    test(
      'the corrected spelling links to the curated row when one exists',
      () async {
        final LocalFood curated = _food('Pork Belly');
        knowledge.catalogue = <LocalFood>[curated];
        matchedAnalysis('Pork Belly');
        recognition.onSpellCheck = (String _, String _) async =>
            (isTypo: true, correctedName: 'Pork Belly');

        final result = await logic.resolveByName(<int>[1], 'prok belly');

        // What a correctly-typed "Pork Belly" entry would have resolved to.
        expect(result.food.id, curated.id);
        expect(result.food.name, 'Pork Belly');
      },
    );

    test('an established spelling is never treated as a typo', () async {
      knowledge.catalogue = const <LocalFood>[];
      matchedAnalysis('Char Kway Teow');
      recognition.onSpellCheck = (String _, String _) async =>
          (isTypo: false, correctedName: '');
      final result = await logic.resolveByName(<int>[1], 'char kuey teow');

      expect(result.typedNameIsTypo, isFalse);
      expect(result.correctedName, '');
      expect(result.food.name, 'char kuey teow');
    });

    test(
      'the spelling gate never runs when the photo does not match',
      () async {
        knowledge.catalogue = const <LocalFood>[];
        bool spellCheckCalled = false;
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food(name),
          priceMin: 0.0,
          priceMax: 0.0,
          isLocal: false,
          confidence: 0.95,
          localConfidence: 0.9,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: false,
          matchConfidence: 0.9,
          observedFood: 'Pepperoni Pizza',
          foodType: 'Food',
          dietaryRestrictions: const <String>[],
        );
        recognition.onSpellCheck = (String _, String _) async {
          spellCheckCalled = true;
          return (isTypo: true, correctedName: 'Pepperoni Pizza');
        };

        final result = await logic.resolveByName(<int>[1], 'nasi lemak');

        // A mismatch is blocked on its own, with the typed name kept as-typed
        // for the warning - the spelling gate has no say there.
        expect(spellCheckCalled, isFalse);
        expect(result.typedNameIsTypo, isFalse);
        expect(result.food.name, 'nasi lemak');
        expect(result.nameMatchesPhoto, isFalse);
      },
    );
  });

  group('FoodRecognitionLogic.enrichCandidate (picker)', () {
    late _FakeRecognitionRepository recognition;
    late _FakeFoodKnowledgeRepository knowledge;
    late FoodRecognitionLogic logic;

    setUp(() {
      recognition = _FakeRecognitionRepository();
      knowledge = _FakeFoodKnowledgeRepository();
      logic = _TestFoodRecognitionLogic(
        _FakeDiscoveryRepositoryFacade(recognition),
        _FakeFoodRepositoryFacade(knowledge),
      );
    });

    test(
      'returns the catalogue row without calling Gemini (fast path)',
      () async {
        final murtabak = _food('Murtabak');
        knowledge.catalogue = <LocalFood>[murtabak];
        bool analyzeByNameCalled = false;
        recognition.onAnalyzeByName = (List<int> _, String name) async {
          analyzeByNameCalled = true;
          return (
            food: _food(name),
            priceMin: 0.0,
            priceMax: 0.0,
            isLocal: true,
            confidence: 1.0,
            localConfidence: 1.0,
            imageQuality: 'good',
            imageQualityIssues: const <String>[],
            nameMatchesPhoto: true,
            matchConfidence: 1.0,
            observedFood: '',
            foodType: 'Food',
            dietaryRestrictions: const <String>[],
          );
        };

        final ({
          LocalFood food,
          String variant,
          double priceMin,
          double priceMax,
          bool fitsCatalogueCategory,
          List<String> dietaryRestrictions,
        })
        result = await logic.enrichCandidate(<int>[1], 'Murtabak');

        expect(result.food.name, 'Murtabak');
        // Picker candidates came from the photo - no verification call needed.
        expect(analyzeByNameCalled, isFalse);
      },
    );

    test(
      'a curated pick carries its own food_dietary_restriction links',
      () async {
        final murtabak = _food('Murtabak');
        knowledge.catalogue = <LocalFood>[murtabak];
        knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
          murtabak.id: <DietaryRestriction>[
            const DietaryRestriction(id: 19, name: 'No Coconut'),
          ],
        };
        recognition.onAnalyzeByName = (List<int> _, String name) async => (
          food: _food('Murtabak (Gemini)'),
          priceMin: 3.0,
          priceMax: 8.0,
          isLocal: true,
          confidence: 1.0,
          localConfidence: 1.0,
          imageQuality: 'good',
          imageQualityIssues: const <String>[],
          nameMatchesPhoto: true,
          matchConfidence: 1.0,
          observedFood: '',
          foodType: 'Food',
          dietaryRestrictions: const <String>['No Gluten'],
        );

        final result = await logic.enrichCandidate(<int>[1], 'Murtabak');

        expect(result.food.id, murtabak.id);
        expect(result.dietaryRestrictions, <String>['No Coconut']);
      },
    );

    test(
      'a picked VARIANT is analysed and still links to its curated row',
      () async {
        final nasiLemak = _food('Nasi Lemak').copyWith(
          id: 19,
          ingredients: 'Rice, coconut milk, anchovies, peanuts, egg',
        );
        knowledge.catalogue = <LocalFood>[nasiLemak];
        knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
          nasiLemak.id: <DietaryRestriction>[
            const DietaryRestriction(id: 11, name: 'No Peanuts'),
          ],
        };
        bool analyzeByNameCalled = false;
        recognition.onAnalyzeByName = (List<int> _, String name) async {
          analyzeByNameCalled = true;
          return (
            food: LocalFood(
              id: 0,
              name: 'Siew Yoke Nasi Lemak',
              description: 'Nasi lemak served with roast pork',
              origin: 'Malaysia',
              culturalBackground: '',
              ingredients:
                  'Rice, coconut milk, anchovies, peanuts, siew yoke (roast pork)',
              category: 'Chinese',
              cookingStyle: 'Braised',
              mealType: 'All-Day Dining',
              foodType: 'Food',
            ),
            priceMin: 9.0,
            priceMax: 14.0,
            isLocal: true,
            confidence: 1.0,
            localConfidence: 1.0,
            imageQuality: 'good',
            imageQualityIssues: const <String>[],
            nameMatchesPhoto: true,
            matchConfidence: 0.95,
            observedFood: '',
            foodType: 'Food',
            dietaryRestrictions: const <String>['No Pork'],
          );
        };

        final result = await logic.enrichCandidate(<int>[
          1,
        ], 'Siew Yoke Nasi Lemak');

        // The pick is a VARIANT, so the photo is analysed for its own facts
        // (the fast path would have left it a plain nasi lemak) ...
        expect(analyzeByNameCalled, isTrue);
        // The picked variant's row was SENT as the stored record ...
        expect(recognition.byNameStoredDish?.name, 'Nasi Lemak');
        // ... while the curated row still owns the dish + its id.
        expect(result.food.id, nasiLemak.id);
        expect(result.food.name, 'Nasi Lemak');
        expect(result.variant, 'Siew Yoke Nasi Lemak');
        expect(result.food.ingredients, contains('roast pork'));
        expect(result.dietaryRestrictions, <String>['No Peanuts', 'No Pork']);
      },
    );
  });

  group(
    'FoodRecognitionLogic.registerNewDishes (Option C catalogue growth)',
    () {
      late _FakeFoodKnowledgeRepository knowledge;
      late _FakeRecognitionRepository recognition;
      late FoodRecognitionLogic logic;

      /// A food as Gemini produces it - not yet a curated row (`id: 0`).
      LocalFood geminiFood(
        String name, {
        List<String> aliases = const <String>[],
        String pronunciationText = '',
      }) => LocalFood(
        id: 0,
        name: name,
        description: 'Description of $name',
        origin: 'Malaysia',
        culturalBackground: '',
        ingredients: '',
        category: 'Malay',
        cookingStyle: 'Frying',
        mealType: 'Breakfast',
        foodType: 'Food',
        pronunciationText: pronunciationText,
        aliases: aliases,
      );

      FoodSubmission submission(
        LocalFood food, {
        double confidence = 0.9,
        bool isLocalFood = true,
        bool isFake = false,
        String? imageUrl,
      }) => FoodSubmission(
        food: food,
        price: 5,
        confidence: confidence,
        isLocalFood: isLocalFood,
        isFake: isFake,
        imageUrl: imageUrl,
      );

      setUp(() {
        recognition = _FakeRecognitionRepository();
        knowledge = _FakeFoodKnowledgeRepository();
        logic = _TestFoodRecognitionLogic(
          _FakeDiscoveryRepositoryFacade(recognition),
          _FakeFoodRepositoryFacade(knowledge),
        );
      });

      test('inserts a genuinely-new high-confidence dish', () async {
        knowledge.catalogue = <LocalFood>[_food('Nasi Lemak')];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(geminiFood('Laksam')),
        ]);

        expect(knowledge.inserted.map((LocalFood f) => f.name), <String>[
          'Laksam',
        ]);
      });

      test('skips a low-confidence dish (0.6 is not enough)', () async {
        knowledge.catalogue = const <LocalFood>[];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(geminiFood('Laksam'), confidence: 0.6),
        ]);

        expect(knowledge.inserted, isEmpty);
      });

      test('skips a variant of an existing dish ("nasi lemak ayam")', () async {
        knowledge.catalogue = <LocalFood>[_food('Nasi Lemak')];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(geminiFood('Nasi Lemak Ayam'), confidence: 0.95),
        ]);

        expect(knowledge.inserted, isEmpty);
      });

      test('skips a dish already in the catalogue (id != 0)', () async {
        final existing = _food('Nasi Lemak');
        knowledge.catalogue = <LocalFood>[existing];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(existing, confidence: 0.95),
        ]);

        expect(knowledge.inserted, isEmpty);
      });

      test('skips non-local and fake dishes', () async {
        knowledge.catalogue = const <LocalFood>[];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(geminiFood('Pizza'), isLocalFood: false, confidence: 0.95),
          submission(geminiFood('Laksam'), confidence: 0.95, isFake: true),
        ]);

        expect(knowledge.inserted, isEmpty);
      });

      test(
        'attaches the submitted dish photo to the new catalogue row',
        () async {
          knowledge.catalogue = const <LocalFood>[];

          await logic.registerNewDishes(<FoodSubmission>[
            submission(
              geminiFood('Laksam'),
              imageUrl:
                  'https://cdn.example.com/storage/landmark-images/photo/a.jpg',
            ),
          ]);

          expect(knowledge.images.length, 1);
          expect(
            knowledge.images.single.localFoodId,
            101,
          ); // the saved row's id
          expect(
            knowledge.images.single.imageName,
            'https://cdn.example.com/storage/landmark-images/photo/a.jpg',
          );
        },
      );

      test('a dish without a photo gets no image link', () async {
        knowledge.catalogue = const <LocalFood>[];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(geminiFood('Laksam')),
        ]);

        expect(knowledge.inserted.length, 1);
        expect(knowledge.images, isEmpty);
      });

      test('persists Gemini aliases as the new row\'s synonyms', () async {
        knowledge.catalogue = const <LocalFood>[];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(
            geminiFood(
              'Bubur Cha Cha',
              aliases: <String>['摩摩喳喳', 'Bobochacha'],
            ),
            confidence: 0.95,
          ),
        ]);

        expect(knowledge.inserted.single.synonyms, <String>[
          '摩摩喳喳',
          'Bobochacha',
        ]);
      });

      test('persists the pronunciation Gemini supplied', () async {
        knowledge.catalogue = const <LocalFood>[];

        await logic.registerNewDishes(<FoodSubmission>[
          submission(
            geminiFood('Roti Canai', pronunciationText: 'roh-tee chah-nai'),
            confidence: 0.95,
          ),
        ]);

        expect(knowledge.inserted.single.pronunciationText, 'roh-tee chah-nai');
      });

      test('verifyNewFoodsOrThrow lets an accepted new dish through', () async {
        await logic.verifyNewFoodsOrThrow(<FoodSubmission>[
          submission(geminiFood('Laksam'), confidence: 0.9),
        ]);
        // No throw - the 3/3 accept passes the pre-submit gate.
      });

      test('verifyNewFoodsOrThrow blocks a rejected new dish', () async {
        recognition.onVerifyOrigin = (String name) => OriginVerification(
          dishName: name,
          verdict: OriginVerdict.reject,
          votesMalaysian: 0,
          directOrigin: (
            dishCase: OriginDishCase.foreign,
            originCountry: 'Indonesia',
            originEthnicity: 'Javanese',
            confidence: 0.9,
          ),
          adjudicate: (
            dishCase: OriginDishCase.foreign,
            actualOriginCountry: 'Indonesia',
            distinguishingNotes: '',
          ),
          knownPattern: (
            isCommonlyMisattributed: true,
            correctOriginIfMisattributed: 'Indonesia',
            reasoning: '',
          ),
        );
        await expectLater(
          logic.verifyNewFoodsOrThrow(<FoodSubmission>[
            submission(geminiFood('Soto Ayam'), confidence: 0.9),
          ]),
          throwsA(isA<LandmarkVerificationRejectedException>()),
        );
      });

      test('verifyNewFoodsOrThrow skips catalogue-linked foods', () async {
        // id != 0 means a direct catalogue link - the gate must not even run.
        recognition.onVerifyOrigin = (String name) {
          throw StateError('the gate should not run for a curated food');
        };
        await logic.verifyNewFoodsOrThrow(<FoodSubmission>[
          submission(_food('Nasi Lemak'), confidence: 0.9),
        ]);
      });
    },
  );

  group('FoodRecognitionLogic.fitsCatalogueCategory', () {
    test('accepts every catalogue dish type', () {
      for (final String type in const <String>[
        'Food',
        'Beverage',
        'Fruit',
        'Dessert',
        'Kuih',
      ]) {
        expect(
          FoodRecognitionLogic.fitsCatalogueCategory(type),
          isTrue,
          reason: type,
        );
      }
      // Case-insensitive and trimmed.
      expect(FoodRecognitionLogic.fitsCatalogueCategory(' beverage '), isTrue);
    });

    test('rejects a non-catalogue type (snack/package/canned drink)', () {
      for (final String type in const <String>[
        'none',
        'Snack',
        'Package',
        'Canned Drink',
        'Biscuit',
        'Other',
      ]) {
        expect(
          FoodRecognitionLogic.fitsCatalogueCategory(type),
          isFalse,
          reason: type,
        );
      }
    });

    test('unknown classification is not a blocker (fail-open)', () {
      expect(FoodRecognitionLogic.fitsCatalogueCategory(null), isTrue);
      expect(FoodRecognitionLogic.fitsCatalogueCategory(''), isTrue);
      expect(FoodRecognitionLogic.fitsCatalogueCategory('   '), isTrue);
    });
  });
}

class _TestFoodRecognitionLogic extends FoodRecognitionLogic {
  _TestFoodRecognitionLogic(this.discovery, this.food);

  final DiscoveryRepositoryFacade discovery;
  final FoodRepositoryFacade food;

  @override
  DiscoveryRepositoryFacade createDiscoveryRepository() => discovery;

  @override
  FoodRepositoryFacade createFoodRepository() => food;
}
