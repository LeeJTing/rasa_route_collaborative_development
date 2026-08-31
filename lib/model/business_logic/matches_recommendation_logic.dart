import 'dart:math' as math;

import 'package:meta/meta.dart' show protected;

import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/matches_recommendation.dart';
import '../../domain_model/region.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/swipe_session.dart';
import '../repositories/discovery_repository_facade.dart';

/// Builds Matches from one state's persisted Swipe Mode likes and real places.
class MatchesRecommendationLogic {
  MatchesRecommendationLogic();

  @protected
  DiscoveryRepositoryFacade createRepository() => DiscoveryRepositoryFacade();

  late final DiscoveryRepositoryFacade _repository = createRepository();

  Future<MatchesRecommendationResult> recommendations(
    MatchesRecommendationRequest request,
  ) async {
    final String touristId = await _repository.currentTouristId() ?? '';
    if (touristId.isEmpty) throw Exception('Sign in to view Matches.');

    final List<Region> regions = await _repository.malaysiaRegions();
    final Region? region = _resolveRegion(regions, request);
    if (region == null) {
      throw Exception('Open Matches from a Malaysian state on the dashboard.');
    }

    final SwipeSession? session = await _repository.getSwipeSession(
      touristId: touristId,
      stateCode: region.code,
    );
    if (session == null || session.likedFoodIds.isEmpty) {
      return MatchesRecommendationResult(
        stateCode: region.code,
        stateName: region.name,
        session: session,
        groups: const <MatchedFoodRecommendations>[],
      );
    }

    final List<LocalFood> foods = await _repository.getLocalFoods();
    final Map<int, LocalFood> foodsById = <int, LocalFood>{
      for (final LocalFood food in foods) food.id: food,
    };
    final List<FoodOccurrence> occurrences =
        (await _repository.foodOccurrences())
            .map((FoodOccurrence value) => _resolveFood(value, foods))
            .where((FoodOccurrence value) => value.localFoodId != 0)
            .where(
              (FoodOccurrence value) =>
                  _contains(region.boundary, value.latitude, value.longitude),
            )
            .toList(growable: false);
    final Map<int, Restaurant> restaurantsById = <int, Restaurant>{
      for (final Restaurant restaurant in await _repository.getRestaurants())
        restaurant.id: restaurant,
    };

    final List<MatchedFoodRecommendations> groups =
        <MatchedFoodRecommendations>[];
    for (final int foodId in session.likedFoodIds) {
      final LocalFood? food = foodsById[foodId];
      if (food == null) continue;
      final List<FoodOccurrence> foodOccurrences = occurrences
          .where((FoodOccurrence value) => value.localFoodId == foodId)
          .toList(growable: false);
      groups.add(
        MatchedFoodRecommendations(
          food: food,
          restaurants: _restaurantsFor(
            foodId,
            foodOccurrences,
            restaurantsById,
            request,
          ),
          submittedLandmarks: _landmarksFor(
            foodOccurrences,
            occurrences,
            foodsById,
            request,
          ),
        ),
      );
    }

    return MatchesRecommendationResult(
      stateCode: region.code,
      stateName: region.name,
      session: session,
      groups: List<MatchedFoodRecommendations>.unmodifiable(groups),
    );
  }

  /// A filled heart removes that food from the device-local state match list.
  Future<SwipeSession> removeLike(SwipeSession session, int foodId) async {
    if (!session.likedFoodIds.contains(foodId)) return session;
    final SwipeSession updated = session.copyWith(
      likedFoodIds: session.likedFoodIds
          .where((int id) => id != foodId)
          .toList(growable: false),
    );
    await _repository.saveSwipeSession(updated);
    return updated;
  }

  List<Restaurant> _restaurantsFor(
    int foodId,
    List<FoodOccurrence> occurrences,
    Map<int, Restaurant> restaurantsById,
    MatchesRecommendationRequest request,
  ) {
    final Map<int, FoodOccurrence> serving = <int, FoodOccurrence>{};
    for (final FoodOccurrence occurrence in occurrences) {
      if (occurrence.source != FoodOccurrenceSource.restaurant) continue;
      final int? id = int.tryParse(occurrence.sourceId);
      if (id != null) serving.putIfAbsent(id, () => occurrence);
    }
    final List<Restaurant> recommendations = <Restaurant>[];
    for (final MapEntry<int, FoodOccurrence> entry in serving.entries) {
      final Restaurant? catalogueRestaurant = restaurantsById[entry.key];
      final List<RestaurantItem> matchedItems =
          catalogueRestaurant?.items
              .where((RestaurantItem item) => item.localFoodId == foodId)
              .toList(growable: false) ??
          <RestaurantItem>[
            RestaurantItem(
              id: 0,
              restaurantId: entry.key,
              localFoodId: foodId,
              foodName: entry.value.foodName,
              price: entry.value.itemPrice,
              currency: 'RM',
              foodCategory: '',
            ),
          ];
      final Restaurant restaurant =
          catalogueRestaurant ??
          Restaurant(
            id: entry.key,
            name: entry.value.placeName,
            category: entry.value.placeCategory ?? '',
            address: '',
            rating: entry.value.placeRating,
            latitude: entry.value.latitude,
            longitude: entry.value.longitude,
            phone: '',
            website: '',
            imageUrl: entry.value.placeImageUrl,
            openingHours: const [],
            items: matchedItems,
          );
      recommendations.add(
        restaurant.copyWith(
          category: _visibleCategory(restaurant.category),
          distanceMetres: _distanceMetres(
            request.origin.latitude,
            request.origin.longitude,
            entry.value.latitude,
            entry.value.longitude,
          ),
          items: matchedItems,
        ),
      );
    }
    return recommendations;
  }

  List<SubmittedLandmarkRecommendation> _landmarksFor(
    List<FoodOccurrence> foodOccurrences,
    List<FoodOccurrence> allOccurrences,
    Map<int, LocalFood> foodsById,
    MatchesRecommendationRequest request,
  ) {
    final Map<String, FoodOccurrence> serving = <String, FoodOccurrence>{};
    for (final FoodOccurrence occurrence in foodOccurrences) {
      if (occurrence.source != FoodOccurrenceSource.submittedLandmark) continue;
      serving.putIfAbsent(occurrence.sourceId, () => occurrence);
    }
    return serving.entries
        .map((MapEntry<String, FoodOccurrence> entry) {
          final FoodOccurrence occurrence = entry.value;
          final List<String> foodNames = allOccurrences
              .where(
                (FoodOccurrence value) =>
                    value.source == FoodOccurrenceSource.submittedLandmark &&
                    value.sourceId == entry.key,
              )
              .map(
                (FoodOccurrence value) =>
                    foodsById[value.localFoodId]?.name ?? value.foodName,
              )
              .toSet()
              .toList(growable: false);
          return SubmittedLandmarkRecommendation(
            id: int.tryParse(entry.key) ?? 0,
            name: occurrence.placeName,
            category: occurrence.placeCategory?.trim().isNotEmpty == true
                ? occurrence.placeCategory!
                : 'Submitted Landmark',
            distanceMetres: _distanceMetres(
              request.origin.latitude,
              request.origin.longitude,
              occurrence.latitude,
              occurrence.longitude,
            ),
            foodNames: foodNames,
            imageUrl: occurrence.placeImageUrl,
            price: occurrence.itemPrice,
          );
        })
        .toList(growable: false);
  }

  Region? _resolveRegion(
    List<Region> regions,
    MatchesRecommendationRequest request,
  ) {
    if (request.stateCode.isNotEmpty) {
      for (final Region region in regions) {
        if (region.code == request.stateCode) return region;
      }
    }
    if (!request.origin.isKnown) return null;
    for (final Region region in regions) {
      if (_contains(
        region.boundary,
        request.origin.latitude,
        request.origin.longitude,
      )) {
        return region;
      }
    }
    return null;
  }

  static FoodOccurrence _resolveFood(
    FoodOccurrence occurrence,
    List<LocalFood> foods,
  ) {
    if (occurrence.localFoodId != 0) return occurrence;
    final String dish = _normalise(occurrence.foodName);
    for (final LocalFood food in foods) {
      if (_normalise(food.name) != dish &&
          !food.synonyms.any((String synonym) => _normalise(synonym) == dish)) {
        continue;
      }
      return FoodOccurrence(
        sourceId: occurrence.sourceId,
        source: occurrence.source,
        placeName: occurrence.placeName,
        localFoodId: food.id,
        foodName: occurrence.foodName,
        latitude: occurrence.latitude,
        longitude: occurrence.longitude,
        placeImageUrl: occurrence.placeImageUrl,
        placeCategory: occurrence.placeCategory,
        placeRating: occurrence.placeRating,
        itemPrice: occurrence.itemPrice,
      );
    }
    return occurrence;
  }

  static bool _contains(
    List<GeoPoint> polygon,
    double latitude,
    double longitude,
  ) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (
      int current = 0, previous = polygon.length - 1;
      current < polygon.length;
      previous = current++
    ) {
      final GeoPoint a = polygon[current];
      final GeoPoint b = polygon[previous];
      if ((a.latitude > latitude) == (b.latitude > latitude)) continue;
      final double intersection =
          (b.longitude - a.longitude) *
              (latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (longitude < intersection) inside = !inside;
    }
    return inside;
  }

  static double _distanceMetres(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    if (fromLatitude == 0 && fromLongitude == 0) return 0;
    const double earthRadiusMetres = 6371000;
    final double latitudeDelta = _radians(toLatitude - fromLatitude);
    final double longitudeDelta = _radians(toLongitude - fromLongitude);
    final double value =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(_radians(fromLatitude)) *
            math.cos(_radians(toLatitude)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusMetres *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  static String _visibleCategory(String raw) => raw
      .split(RegExp(r'[,·|/]'))
      .map((String value) => value.trim())
      .where(
        (String value) => !value.toLowerCase().contains(RegExp(r'\bhalal\b')),
      )
      .where((String value) => value.isNotEmpty)
      .join(', ');

  static double _radians(double degrees) => degrees * math.pi / 180;

  static String _normalise(String value) => value.trim().toLowerCase();
}
