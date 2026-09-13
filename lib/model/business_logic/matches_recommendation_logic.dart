import 'dart:math' as math;

import 'package:meta/meta.dart' show protected;

import '../../core/place_category.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/matches_recommendation.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/swipe_session.dart';
import '../repositories/discovery_repository_facade.dart';
import 'opening_hours_logic.dart';

/// Builds Matches from one state's persisted Swipe Mode likes and real places.
class MatchesRecommendationLogic {
  MatchesRecommendationLogic();

  @protected
  DiscoveryRepositoryFacade createRepository() => DiscoveryRepositoryFacade();

  @protected
  DateTime currentTime() => DateTime.now();

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
    final List<Object> placeData = await Future.wait(<Future<Object>>[
      _repository.foodOccurrences(),
      _repository.openingHoursByPlace(),
      _repository.getRestaurants(),
    ]);
    final Map<String, List<OpeningHour>> hoursByPlace =
        placeData[1] as Map<String, List<OpeningHour>>;
    final DateTime malaysiaNow = currentTime().toUtc().add(
      const Duration(hours: 8),
    );
    final List<FoodOccurrence> occurrences =
        (placeData[0] as List<FoodOccurrence>)
            .map((FoodOccurrence value) => _resolveFood(value, foods))
            .where((FoodOccurrence value) => value.localFoodId != 0)
            .where(
              (FoodOccurrence value) =>
                  _contains(region.boundary, value.latitude, value.longitude),
            )
            .where(
              (FoodOccurrence value) =>
                  !OpeningHoursLogic.isConfidentlyClosedAt(
                    hoursByPlace[_placeKey(value)],
                    malaysiaNow,
                  ),
            )
            .toList(growable: false);
    final Map<int, Restaurant> restaurantsById = <int, Restaurant>{
      for (final Restaurant restaurant in placeData[2] as List<Restaurant>)
        restaurant.id: restaurant,
    };
    final Map<int, double> restaurantStartingPrices = _restaurantStartingPrices(
      occurrences,
    );

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
          restaurantStartingPrices: restaurantStartingPrices,
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

  static String _placeKey(FoodOccurrence occurrence) =>
      occurrence.source == FoodOccurrenceSource.restaurant
      ? 'restaurant:${occurrence.sourceId}'
      : 'submittedLandmark:${occurrence.sourceId}';

  Map<int, double> _restaurantStartingPrices(List<FoodOccurrence> occurrences) {
    final Map<int, double> prices = <int, double>{};
    for (final FoodOccurrence occurrence in occurrences) {
      if (occurrence.source != FoodOccurrenceSource.restaurant) continue;
      final int? restaurantId = int.tryParse(occurrence.sourceId);
      final double? price = occurrence.itemPrice;
      if (restaurantId == null || price == null || price <= 0) continue;
      final double? current = prices[restaurantId];
      if (current == null || price < current) {
        prices[restaurantId] = price;
      }
    }
    return Map<int, double>.unmodifiable(prices);
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
    final Map<int, List<FoodOccurrence>> serving =
        <int, List<FoodOccurrence>>{};
    for (final FoodOccurrence occurrence in occurrences) {
      if (occurrence.source != FoodOccurrenceSource.restaurant) continue;
      final int? id = int.tryParse(occurrence.sourceId);
      if (id != null) {
        serving.putIfAbsent(id, () => <FoodOccurrence>[]).add(occurrence);
      }
    }
    final List<Restaurant> recommendations = <Restaurant>[];
    for (final MapEntry<int, List<FoodOccurrence>> entry in serving.entries) {
      final FoodOccurrence occurrence = entry.value.first;
      final Restaurant? catalogueRestaurant = restaurantsById[entry.key];
      final List<RestaurantItem> catalogueItems =
          catalogueRestaurant?.items
              .where((RestaurantItem item) => item.localFoodId == foodId)
              .toList(growable: false) ??
          const <RestaurantItem>[];
      // `getRestaurants()` intentionally returns lightweight summaries, so
      // its Restaurant objects normally have no menu items. The occurrence
      // query already carries every matching restaurant-item price; use those
      // rows instead of incorrectly presenting a real price as unavailable.
      final List<RestaurantItem> matchedItems = catalogueItems.isNotEmpty
          ? catalogueItems
          : entry.value
                .map(
                  (FoodOccurrence item) => RestaurantItem(
                    id: 0,
                    restaurantId: entry.key,
                    localFoodId: foodId,
                    foodName: item.foodName,
                    price: item.itemPrice,
                    currency: 'RM',
                    foodCategory: '',
                  ),
                )
                .toList(growable: false);
      final Restaurant restaurant =
          catalogueRestaurant ??
          Restaurant(
            id: entry.key,
            name: occurrence.placeName,
            category: occurrence.placeCategory ?? '',
            address: '',
            rating: occurrence.placeRating,
            latitude: occurrence.latitude,
            longitude: occurrence.longitude,
            phone: '',
            website: '',
            imageUrl: occurrence.placeImageUrl,
            openingHours: const [],
            items: matchedItems,
          );
      recommendations.add(
        _withRecommendationDetails(
          restaurant,
          category: _visibleCategory(restaurant.category),
          distanceMetres: request.origin.isKnown
              ? _distanceMetres(
                  request.origin.latitude,
                  request.origin.longitude,
                  occurrence.latitude,
                  occurrence.longitude,
                )
              : null,
          items: matchedItems,
        ),
      );
    }
    return recommendations;
  }

  Restaurant _withRecommendationDetails(
    Restaurant restaurant, {
    required String category,
    required double? distanceMetres,
    required List<RestaurantItem> items,
  }) => Restaurant(
    id: restaurant.id,
    name: restaurant.name,
    category: category,
    address: restaurant.address,
    rating: restaurant.rating,
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    phone: restaurant.phone,
    website: restaurant.website,
    imageUrl: restaurant.imageUrl,
    openingHours: restaurant.openingHours,
    distanceMetres: distanceMetres,
    reviewCount: restaurant.reviewCount,
    items: items,
  );

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
          // Everything this landmark serves, fetched once: the dishes AND the
          // categories the majority pick is made from, so the two cannot
          // disagree (`majorityCategory`).
          final List<FoodOccurrence> allForLandmark = allOccurrences
              .where(
                (FoodOccurrence value) =>
                    value.source == FoodOccurrenceSource.submittedLandmark &&
                    value.sourceId == entry.key,
              )
              .toList(growable: false);
          final List<SubmittedLandmarkDish> dishes = _dishesOf(
            allForLandmark,
            foodsById,
          );
          return SubmittedLandmarkRecommendation(
            id: int.tryParse(entry.key) ?? 0,
            name: occurrence.placeName,
            category: majorityCategory(
              allForLandmark.map(
                (FoodOccurrence value) => value.itemFoodCategory ?? '',
              ),
              fallback: occurrence.placeCategory?.trim() ?? '',
            ),
            // The landmark presentation model uses infinity as its sortable
            // "distance unavailable" value, whereas Restaurant can retain
            // null directly. Never calculate from the 0,0 unknown sentinel.
            distanceMetres: request.origin.isKnown
                ? _distanceMetres(
                    request.origin.latitude,
                    request.origin.longitude,
                    occurrence.latitude,
                    occurrence.longitude,
                  )
                : double.infinity,
            dishes: dishes,
            imageUrl: occurrence.placeImageUrl,
            // The tourist-supplied address, shown under the name exactly
            // like a restaurant card's own address row.
            address: occurrence.placeAddress ?? '',
            // The starting price is the LOWEST dish price, so the card
            // reads exactly like a restaurant's "From RM x".
            price: _startingDishPrice(dishes),
          );
        })
        .toList(growable: false);
  }

  /// The landmark's dishes as the cards list them: the catalogue name when
  /// the dish links to one, else the recorded text, trimmed and de-duplicated
  /// by name (first occurrence wins), each with its own price and photo.
  List<SubmittedLandmarkDish> _dishesOf(
    Iterable<FoodOccurrence> items,
    Map<int, LocalFood> foodsById,
  ) {
    final List<SubmittedLandmarkDish> dishes = <SubmittedLandmarkDish>[];
    final Set<String> seen = <String>{};
    for (final FoodOccurrence item in items) {
      final String name = (foodsById[item.localFoodId]?.name ?? item.foodName)
          .trim();
      if (name.isEmpty || !seen.add(name)) continue;
      dishes.add(
        SubmittedLandmarkDish(
          name: name,
          price: item.itemPrice,
          imageUrl: item.itemImageUrl,
          ingredients: item.itemIngredients,
          description: item.itemDescription,
        ),
      );
    }
    return dishes;
  }

  /// The LOWEST of the dishes' known prices - the "From RM x" starting
  /// price, the same figure a restaurant card shows. Null while no dish has
  /// a price.
  double? _startingDishPrice(List<SubmittedLandmarkDish> dishes) {
    double? lowest;
    for (final SubmittedLandmarkDish dish in dishes) {
      final double? price = dish.price;
      if (price == null || price <= 0) continue;
      if (lowest == null || price < lowest) lowest = price;
    }
    return lowest;
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
        foodType: food.foodType,
        latitude: occurrence.latitude,
        longitude: occurrence.longitude,
        placeImageUrl: occurrence.placeImageUrl,
        placeCategory: occurrence.placeCategory,
        placeRating: occurrence.placeRating,
        placeAddress: occurrence.placeAddress,
        itemPrice: occurrence.itemPrice,
        // The per-dish extras must survive the id resolution - the cards
        // show this dish's own photo, description and ingredients.
        itemImageUrl: occurrence.itemImageUrl,
        itemIngredients: occurrence.itemIngredients,
        itemDescription: occurrence.itemDescription,
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
