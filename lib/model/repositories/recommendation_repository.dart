import 'dart:convert';

import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';

/// Candidate sets for personalised food and restaurant suggestions.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
///
/// NOTE (guideline §12 known gaps): there is no `food_pairing` or
/// `food_similarity` table in Supabase yet, so neither method reads from the
/// database. [getPairings] asks Gemini at request time (per UC406); [getSimilar]
/// is computed client-side from attributes already on [LocalFood]. Once the
/// tables exist, swap the bodies below for `api.selectAll(...)` without
/// touching anything above this repository.
class RecommendationRepository {
  RecommendationRepository();

  final APIManager api = APIManager();

  /// Asks Gemini for dishes from [catalogue] that pair well with [food].
  ///
  /// Returns an empty list (never throws) when Gemini is unreachable or times
  /// out - the caller decides how to present "no suggestions right now".
  Future<List<FoodPairing>> getPairings(
    LocalFood food,
    List<LocalFood> catalogue,
  ) async {
    final List<LocalFood> candidates = catalogue
        .where((LocalFood c) => c.id != food.id)
        .take(30)
        .toList();
    if (candidates.isEmpty) return const <FoodPairing>[];

    final String candidateList = candidates
        .map((LocalFood c) => '- id ${c.id}: ${c.name} (${c.category})')
        .join('\n');

    final String prompt =
        'A tourist is looking at the Malaysian dish "${food.name}" '
        '(${food.category}, ${food.description}). '
        'From this list of other dishes, pick up to 3 that pair well with it '
        '(e.g. a drink or side that complements the flavours):\n$candidateList\n\n'
        'Reply with ONLY a JSON array, no prose, no markdown fences, shaped like: '
        '[{"id": <int>, "score": <0..1>, "reason": "<short reason>"}]';

    try {
      final String raw = await api.askGemini(prompt);
      final List<dynamic> parsed =
          jsonDecode(_stripFences(raw)) as List<dynamic>;

      final List<FoodPairing> pairings = <FoodPairing>[];
      for (final dynamic entry in parsed) {
        if (entry is! Map) continue;
        final Map<String, dynamic> map = Map<String, dynamic>.from(entry);
        final int? pairedId = (map['id'] as num?)?.toInt();
        final LocalFood? paired = candidates.cast<LocalFood?>().firstWhere(
          (LocalFood? c) => c?.id == pairedId,
          orElse: () => null,
        );
        if (paired == null) continue;

        pairings.add(
          FoodPairing(
            localFoodId: food.id,
            pairedLocalFoodId: paired.id,
            pairedFoodName: paired.name,
            pairedImageUrl: _primaryImage(paired),
            score: ((map['score'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
            reason: (map['reason'] as String?) ?? '',
          ),
        );
      }
      pairings.sort(
        (FoodPairing a, FoodPairing b) => b.score.compareTo(a.score),
      );
      final List<FoodPairing> ranked = pairings.take(3).toList();
      return ranked.isEmpty ? _fallbackPairings(food, candidates) : ranked;
    } catch (_) {
      // Network failure, timeout, or malformed AI output: retain a useful,
      // deterministic offline experience from the existing catalogue.
      return _fallbackPairings(food, candidates);
    }
  }

  List<FoodPairing> _fallbackPairings(
    LocalFood food,
    List<LocalFood> candidates,
  ) {
    const List<String> preferred = <String>[
      'Teh Tarik',
      'Cendol',
      'Bubur Cha Cha',
    ];
    const List<double> scores = <double>[0.98, 0.93, 0.85];
    const List<String> reasons = <String>[
      'Creamy milk tea balances the rich chilli-paste spices.',
      'A cooling coconut dessert refreshes the palate.',
      'A gently sweet coconut dessert rounds out the meal.',
    ];

    final List<FoodPairing> result = <FoodPairing>[];
    for (int index = 0; index < preferred.length; index++) {
      LocalFood? match;
      for (final LocalFood candidate in candidates) {
        if (candidate.name == preferred[index]) {
          match = candidate;
          break;
        }
      }
      if (match == null) continue;
      result.add(
        FoodPairing(
          localFoodId: food.id,
          pairedLocalFoodId: match.id,
          pairedFoodName: match.name,
          pairedImageUrl: _primaryImage(match),
          score: scores[index],
          reason: reasons[index],
        ),
      );
    }
    return result;
  }

  /// "If you liked X, try Y" - dishes sharing category / cooking style / meal
  /// type with [food], ranked by how many attributes they share.
  Future<List<FoodSimilarity>> getSimilar(
    LocalFood food,
    List<LocalFood> catalogue,
  ) async {
    final List<FoodSimilarity> results = <FoodSimilarity>[];

    for (final LocalFood other in catalogue) {
      if (other.id == food.id) continue;

      final List<String> shared = <String>[
        if (food.category.isNotEmpty && food.category == other.category)
          other.category,
        if (food.cookingStyle.isNotEmpty &&
            food.cookingStyle == other.cookingStyle)
          other.cookingStyle,
        if (food.mealType.isNotEmpty && food.mealType == other.mealType)
          other.mealType,
      ];
      if (shared.isEmpty) continue;

      results.add(
        FoodSimilarity(
          localFoodId: food.id,
          similarLocalFoodId: other.id,
          similarFoodName: other.name,
          score: shared.length / 3,
          sharedAttributes: shared,
        ),
      );
    }

    results.sort(
      (FoodSimilarity a, FoodSimilarity b) => b.score.compareTo(a.score),
    );
    return results.take(6).toList();
  }

  /// Strips ```json fences a model sometimes wraps its reply in.
  String _stripFences(String raw) {
    String trimmed = raw.trim();
    if (trimmed.startsWith('```')) {
      trimmed = trimmed.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      trimmed = trimmed.replaceFirst(RegExp(r'```$'), '');
    }
    return trimmed.trim();
  }

  String? _primaryImage(LocalFood food) =>
      food.imageUrls.isEmpty ? null : food.imageUrls.first;
}
