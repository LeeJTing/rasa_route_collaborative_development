import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_recognition_result.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
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

  @override
  Future<FoodAnalysisResponse> identifyFoodName(List<int> imageBytes) =>
      onIdentify!(imageBytes);

  @override
  Future<FoodAnalysis> analyzeFoodFull(List<int> imageBytes) =>
      onAnalyzeFull!(imageBytes);

  @override
  Future<FoodAnalysis> analyzeFoodByName(List<int> imageBytes, String name) =>
      onAnalyzeByName!(imageBytes, name);
}

/// Fake catalogue repository - replaces Supabase's `getFoods` lookup with a
/// controllable in-memory catalogue list, and records `insertFood` calls.
class _FakeFoodKnowledgeRepository extends FoodKnowledgeRepository {
  List<LocalFood> catalogue = const <LocalFood>[];
  final List<LocalFood> inserted = <LocalFood>[];

  @override
  Future<List<LocalFood>> getFoods() async => catalogue;

  @override
  Future<LocalFood?> insertFood(LocalFood food) async {
    inserted.add(food);
    return food;
  }
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
}) => FoodAnalysisResponse(
  dish: dish,
  variant: '',
  description: '',
  origin: '',
  cookingStyle: '',
  mealType: '',
  foodCategory: 'Malay',
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
      logic = FoodRecognitionLogic(
        discoveryRepository: DiscoveryRepositoryFacade(
          recognition: recognition,
        ),
        foodRepository: FoodRepositoryFacade(knowledge: knowledge),
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
        );

        final FoodRecognitionResult result = await logic.recognizeFood(<int>[
          1,
        ]);

        expect(result.isLocalFood, isFalse);
        expect(result.candidates.length, 1);
        expect(result.candidates.single.name, 'Roti Canai');
      },
    );

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
        );
      };

      final FoodRecognitionResult result = await logic.recognizeFood(<int>[1]);

      expect(analyzeFullCalled, isTrue);
      expect(result.candidates.single.name, 'Murtabak (verified)');
      expect(result.confidence, 0.95);
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
  });

  group('FoodRecognitionLogic.resolveByName (manual entry)', () {
    late _FakeRecognitionRepository recognition;
    late _FakeFoodKnowledgeRepository knowledge;
    late FoodRecognitionLogic logic;

    setUp(() {
      recognition = _FakeRecognitionRepository();
      knowledge = _FakeFoodKnowledgeRepository();
      logic = FoodRecognitionLogic(
        discoveryRepository: DiscoveryRepositoryFacade(
          recognition: recognition,
        ),
        foodRepository: FoodRepositoryFacade(knowledge: knowledge),
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
      );

      final result = await logic.resolveByName(<int>[1], 'char kuey teow');

      expect(result.nameMatchesPhoto, isTrue);
      expect(result.food.name, 'Char Kway Teow');
    });
  });

  group('FoodRecognitionLogic.enrichCandidate (picker)', () {
    late _FakeRecognitionRepository recognition;
    late _FakeFoodKnowledgeRepository knowledge;
    late FoodRecognitionLogic logic;

    setUp(() {
      recognition = _FakeRecognitionRepository();
      knowledge = _FakeFoodKnowledgeRepository();
      logic = FoodRecognitionLogic(
        discoveryRepository: DiscoveryRepositoryFacade(
          recognition: recognition,
        ),
        foodRepository: FoodRepositoryFacade(knowledge: knowledge),
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
          );
        };

        final ({LocalFood food, double priceMin, double priceMax}) result =
            await logic.enrichCandidate(<int>[1], 'Murtabak');

        expect(result.food.name, 'Murtabak');
        // Picker candidates came from the photo - no verification call needed.
        expect(analyzeByNameCalled, isFalse);
      },
    );
  });

  group(
    'FoodRecognitionLogic.registerNewDishes (Option C catalogue growth)',
    () {
      late _FakeFoodKnowledgeRepository knowledge;
      late FoodRecognitionLogic logic;

      /// A food as Gemini produces it - not yet a curated row (`id: 0`).
      LocalFood geminiFood(String name) => _food(name).copyWith(id: 0);

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
        knowledge = _FakeFoodKnowledgeRepository();
        logic = FoodRecognitionLogic(
          discoveryRepository: DiscoveryRepositoryFacade(
            recognition: _FakeRecognitionRepository(),
          ),
          foodRepository: FoodRepositoryFacade(knowledge: knowledge),
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
    },
  );
}
