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
  OriginVerification Function(String)? onVerifyOrigin;

  @override
  Future<FoodAnalysisResponse> identifyFoodName(List<int> imageBytes) =>
      onIdentify!(imageBytes);

  @override
  Future<FoodAnalysis> analyzeFoodFull(List<int> imageBytes) =>
      onAnalyzeFull!(imageBytes);

  @override
  Future<FoodAnalysis> analyzeFoodByName(List<int> imageBytes, String name) =>
      onAnalyzeByName!(imageBytes, name);

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

  /// Curated `food_dietary_restriction` links per food id - empty by default,
  /// so tests that do not care see no dietary tags.
  Map<int, List<DietaryRestriction>> foodRestrictionLinks =
      const <int, List<DietaryRestriction>>{};

  @override
  Future<List<LocalFood>> getFoods() async => catalogue;

  @override
  Future<LocalFood?> insertFood(LocalFood food) async {
    inserted.add(food);
    return food;
  }

  /// Not an override - `FoodKnowledgeRepository` has no such method (the
  /// facade routes it to the dietary-restriction repository), but the fake
  /// exposes the stubbed links so [FoodRecognitionLogic._dietaryTagsFor] can
  /// be exercised without a network call.
  Future<List<DietaryRestriction>> foodDietaryRestrictions(
    int localFoodId,
  ) async =>
      foodRestrictionLinks[localFoodId] ?? const <DietaryRestriction>[];
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
  Future<List<DietaryRestriction>> foodDietaryRestrictions(
    int localFoodId,
  ) => fakeKnowledge.foodDietaryRestrictions(localFoodId);
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

    test('a curated dish matched by the full analysis ignores Gemini\'s '
        'free-text tags and uses its own links instead', () async {
      final bubur = _food('Bubur Cha Cha');
      knowledge.catalogue = <LocalFood>[bubur];
      knowledge.foodRestrictionLinks = <int, List<DietaryRestriction>>{
        bubur.id: <DietaryRestriction>[
          const DietaryRestriction(id: 19, name: 'No Coconut'),
        ],
      };
      recognition.onIdentify = (_) async =>
          _quickResponse(dish: 'Bubur Cha Cha', confidence: 0.4);
      // The full analysis judges it a curated dish, but Gemini's own tags
      // are noisy - it lists restrictions the dish is FREE of.
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

      // Curated wins: the dish resolves to the catalogue row and its own
      // link is the ONLY tag - the gluten/egg noise is dropped so the tourist
      // is not warned about restrictions the dish does not violate.
      expect(result.candidates.single.id, bubur.id);
      expect(result.dietaryRestrictions, <String>['No Coconut']);
    });

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
      // Once verified, the curated catalogue row's details are preferred.
      expect(result.food.name, 'Murtabak');
      expect(result.priceMin, 0.0);
    });

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

    test('a curated typed dish carries its own food_dietary_restriction links '
        '(never Gemini\'s tags)', () async {
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
        // Gemini's noisy tags - must be ignored for the curated row.
        dietaryRestrictions: const <String>['No Pork', 'No Gluten'],
      );

      final result = await logic.resolveByName(<int>[1], 'Murtabak');

      expect(result.food.id, murtabak.id);
      expect(result.dietaryRestrictions, <String>['No Pork']);
    });
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
  });

  group(
    'FoodRecognitionLogic.registerNewDishes (Option C catalogue growth)',
    () {
      late _FakeFoodKnowledgeRepository knowledge;
      late _FakeRecognitionRepository recognition;
      late FoodRecognitionLogic logic;

      /// A food as Gemini produces it - not yet a curated row (`id: 0`).
      LocalFood geminiFood(String name) => LocalFood(
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
      );

      FoodSubmission submission(
        LocalFood food, {
        double confidence = 0.9,
        bool isLocalFood = true,
        bool isFake = false,
      }) => FoodSubmission(
        food: food,
        price: 5,
        confidence: confidence,
        isLocalFood: isLocalFood,
        isFake: isFake,
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
