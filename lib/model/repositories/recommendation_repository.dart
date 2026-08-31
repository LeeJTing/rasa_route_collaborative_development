import 'dart:convert';

import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';

class RecommendationRepository {
  RecommendationRepository();

  final APIManager api = APIManager();

  Future<List<FoodPairing>> getPairings(
      LocalFood food,
      List<LocalFood> catalogue, {
        List<int> touristDietaryRestrictionIds = const <int>[],
        Map<int, List<int>> foodDietaryRestrictionIds = const <int, List<int>>{},
        int maximumResults = 5,
      }) async {
    final int maxResults = maximumResults < 1
        ? 1
        : (maximumResults > 5 ? 5 : maximumResults);

    // Confirmed dietary conflicts are excluded up front - dietary safety
    // outranks pairing quality and is never left to the model alone.
    final Set<int> touristRestrictionIds = touristDietaryRestrictionIds.toSet();
    final List<LocalFood> candidates = catalogue
        .where((LocalFood c) => c.id != food.id)
        .where(
          (LocalFood c) => !_hasDietaryConflict(
        c,
        foodDietaryRestrictionIds,
        touristRestrictionIds,
      ),
    )
        .take(40)
        .toList(growable: false);
    if (candidates.isEmpty) return const <FoodPairing>[];

    final String raw = await api.gemini.generateFoodPairings(
      selected: food,
      candidates: candidates,
    );
    final List<FoodPairing> parsed = parsePairings(
      raw,
      selected: food,
      candidates: candidates,
      maximumResults: maxResults,
    );
    // Gemini is fallible: it may answer with the empty "no suitable pairings"
    // response, or return ids outside CANDIDATES that validation drops - even
    // when eligible candidates remain. Never leave the tourist without a
    // pairing when at least one candidate exists: fall back to a
    // deterministic, dietary-safe pick.
    if (parsed.isNotEmpty) return parsed;
    return fallbackPairings(
      food,
      candidates,
      maximumResults: maxResults,
    );
  }

  /// Whether [candidate]'s `food_dietary_restriction` ids intersect the
  /// tourist's chosen restriction ids. True = confirmed conflict = excluded.
  bool _hasDietaryConflict(
      LocalFood candidate,
      Map<int, List<int>> foodDietaryRestrictionIds,
      Set<int> touristRestrictionIds,
      ) {
    if (touristRestrictionIds.isEmpty) return false;
    final List<int> ids =
        foodDietaryRestrictionIds[candidate.id] ?? const <int>[];
    return ids.any(touristRestrictionIds.contains);
  }

  /// Deterministic fallback for when Gemini returns no usable pairing but
  /// eligible [candidates] remain: rank candidates by how many attributes
  /// they share with [selected] (category, cooking style, meal type) and
  /// return the top ones. Guarantees at least one pairing whenever at least
  /// one candidate is supplied, so the "no suitable pairing" message only
  /// appears when dietary filtering has removed every candidate.
  @visibleForTesting
  List<FoodPairing> fallbackPairings(
    LocalFood selected,
    List<LocalFood> candidates, {
    required int maximumResults,
  }) {
    if (candidates.isEmpty) return const <FoodPairing>[];

    final List<({LocalFood food, int shared})> scored = candidates
        .map(
          (LocalFood c) => (
            food: c,
            shared: _sharedAttributeCount(selected, c),
          ),
        )
        .toList(growable: false);
    scored.sort((a, b) {
      final int byShared = b.shared.compareTo(a.shared);
      if (byShared != 0) return byShared;
      return a.food.id.compareTo(b.food.id);
    });

    final int take = scored.length < maximumResults
        ? scored.length
        : maximumResults;
    final List<FoodPairing> pairings = <FoodPairing>[];
    for (int index = 0; index < take; index++) {
      final LocalFood candidate = scored[index].food;
      pairings.add(
        FoodPairing(
          localFoodId: selected.id,
          pairedLocalFoodId: candidate.id,
          pairedFoodName: candidate.name,
          rank: index + 1,
          matchPercentage: _fallbackPercentage(scored[index].shared),
          reason: _fallbackReason(selected, candidate),
          dietaryStatus: FoodPairingDietaryStatus.compatible,
          warning: null,
        ),
      );
    }
    return pairings;
  }

  /// How many of category / cooking style / meal type [a] and [b] share.
  int _sharedAttributeCount(LocalFood a, LocalFood b) {
    int count = 0;
    if (a.category.isNotEmpty && a.category == b.category) count++;
    if (a.cookingStyle.isNotEmpty && a.cookingStyle == b.cookingStyle) count++;
    if (a.mealType.isNotEmpty && a.mealType == b.mealType) count++;
    return count;
  }

  /// Fallback strength scales with shared attributes, capped well below what
  /// a confident Gemini pairing would claim.
  int _fallbackPercentage(int shared) => switch (shared) {
    3 => 78,
    2 => 72,
    1 => 65,
    _ => 58,
  };

  /// A short, honest reason for a fallback pairing.
  String _fallbackReason(LocalFood selected, LocalFood candidate) {
    final List<String> shared = <String>[
      if (selected.category.isNotEmpty &&
          selected.category == candidate.category)
        selected.category,
      if (selected.cookingStyle.isNotEmpty &&
          selected.cookingStyle == candidate.cookingStyle)
        selected.cookingStyle,
      if (selected.mealType.isNotEmpty &&
          selected.mealType == candidate.mealType)
        selected.mealType,
    ];
    if (shared.isEmpty) return 'Pairs well with ${selected.name}.';
    return 'Shares the same ${shared.join(' and ')} as ${selected.name} - a natural pairing.';
  }

  @visibleForTesting
  List<FoodPairing> parsePairings(
      String raw, {
        required LocalFood selected,
        required List<LocalFood> candidates,
        required int maximumResults,
      }) {
    final Map<String, dynamic> decoded;
    try {
      final Object? parsed = jsonDecode(_stripFences(raw));
      decoded = parsed is Map<String, dynamic>
          ? parsed
          : <String, dynamic>{};
    } catch (_) {
      return const <FoodPairing>[];
    }

    final List<dynamic>? entries = decoded['recommendations'] as List<dynamic>?;
    if (entries == null) return const <FoodPairing>[];

    final List<FoodPairing> pairings = <FoodPairing>[];
    final Set<int> seen = <int>{};
    for (final dynamic entry in entries) {
      if (entry is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(entry);

      final int? pairedId = (map['foodId'] as num?)?.toInt();
      final LocalFood? paired = _candidateById(candidates, pairedId);
      if (paired == null ||
          paired.id == selected.id ||
          !seen.add(paired.id)) {
        continue;
      }

      final bool isWarning = map['dietaryStatus'] == 'warning';
      final int rawPercentage = (map['matchPercentage'] as num?)?.toInt() ?? 0;
      final int percentage = rawPercentage < 0
          ? 0
          : (rawPercentage > 100 ? 100 : rawPercentage);
      final String reason = (map['reason'] as String?)?.trim() ?? '';
      final String? warning = (map['warning'] as String?)?.trim();

      pairings.add(
        FoodPairing(
          localFoodId: selected.id,
          pairedLocalFoodId: paired.id,
          pairedFoodName: paired.name,
          rank: 0, // reassigned after sorting
          matchPercentage: percentage,
          reason: reason.isEmpty
              ? 'Pairs well with ${selected.name}.'
              : reason,
          dietaryStatus: isWarning
              ? FoodPairingDietaryStatus.warning
              : FoodPairingDietaryStatus.compatible,
          warning: isWarning
              ? (warning == null || warning.isEmpty)
              ? _defaultWarning
              : warning
              : null,
        ),
      );
    }

    // Highest percentage first; ties keep CANDIDATES order.
    pairings.sort(
          (FoodPairing a, FoodPairing b) =>
          b.matchPercentage.compareTo(a.matchPercentage),
    );
    final int take = pairings.length < maximumResults
        ? pairings.length
        : maximumResults;
    // Rebuild with consecutive ranks (domain models carry no behaviour).
    return <FoodPairing>[
      for (int index = 0; index < take; index++)
        FoodPairing(
          localFoodId: pairings[index].localFoodId,
          pairedLocalFoodId: pairings[index].pairedLocalFoodId,
          pairedFoodName: pairings[index].pairedFoodName,
          rank: index + 1,
          matchPercentage: pairings[index].matchPercentage,
          reason: pairings[index].reason,
          dietaryStatus: pairings[index].dietaryStatus,
          warning: pairings[index].warning,
        ),
    ];
  }

  LocalFood? _candidateById(List<LocalFood> candidates, int? id) {
    if (id == null) return null;
    for (final LocalFood candidate in candidates) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  static const String _defaultWarning =
      'Allergen or preparation information is incomplete; confirm with the seller before ordering.';

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
    return results.take(10).toList();
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
}
