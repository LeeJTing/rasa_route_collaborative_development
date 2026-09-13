import 'dart:math' as math;

import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/matches_recommendation_tab.dart';
import '../domain_model/matches_recommendation.dart';
import '../domain_model/restaurant.dart';
import '../domain_model/restaurant_item.dart';
import '../domain_model/swipe_session.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import 'current_location_facade.dart';

enum MatchesRestaurantSort { distance, price, preference, rating }

enum MatchesLandmarkSort { distance, name }

enum MatchesSortDirection { ascending, descending }

/// Presentation state for the state-scoped Matches Recommendation page.
///
/// All data comes from one DiscoveryLogicFacade. The ViewModel only owns
/// presentation concerns: selected tab, sorting, radius expansion and how many
/// entries are visible inside each liked-food group.
class MatchesRecommendationViewModel extends BaseViewModel {
  MatchesRecommendationViewModel();

  @protected
  DiscoveryLogicFacade createDiscoveryLogic() => DiscoveryLogicFacade();

  static const int initialVisibleCount = 2;
  static const int additionalVisibleCount = 2;
  static const double initialRadiusKm = 1;

  late final DiscoveryLogicFacade discoveryLogic = createDiscoveryLogic();
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  MatchesRecommendationRequest? _request;
  MatchesRecommendationResult? _result;
  MatchesRecommendationTab _selectedTab = MatchesRecommendationTab.restaurants;
  MatchesRestaurantSort _restaurantSort = MatchesRestaurantSort.distance;
  MatchesSortDirection _restaurantSortDirection =
      MatchesSortDirection.ascending;
  MatchesLandmarkSort _landmarkSort = MatchesLandmarkSort.distance;
  MatchesSortDirection _landmarkSortDirection = MatchesSortDirection.ascending;
  final Map<int, double> _restaurantRadiusKm = <int, double>{};
  final Map<int, double> _landmarkRadiusKm = <int, double>{};
  final Map<int, double> _initialRestaurantRadiusKm = <int, double>{};
  final Map<int, double> _initialLandmarkRadiusKm = <int, double>{};
  final Map<int, int> _visibleRestaurantCount = <int, int>{};
  final Map<int, int> _visibleLandmarkCount = <int, int>{};
  int? _loadingGroupId;

  void configureRequest(MatchesRecommendationRequest request) {
    _request ??= request;
  }

  MatchesRecommendationTab get selectedTab => _selectedTab;
  MatchesRestaurantSort get restaurantSort => _restaurantSort;
  MatchesSortDirection get restaurantSortDirection => _restaurantSortDirection;
  MatchesLandmarkSort get landmarkSort => _landmarkSort;
  MatchesSortDirection get landmarkSortDirection => _landmarkSortDirection;
  bool isLoadingMore(int foodId) => _loadingGroupId == foodId;
  String get stateName => _result?.stateName ?? _request?.stateName ?? '';
  bool get hasLikedFoods => _result?.groups.isNotEmpty ?? false;

  double radiusFor(int foodId) =>
      _selectedTab == MatchesRecommendationTab.restaurants
      ? _restaurantRadiusKm[foodId] ?? initialRadiusKm
      : _landmarkRadiusKm[foodId] ?? initialRadiusKm;

  List<MatchedFoodRecommendations> get groups =>
      _result?.groups ?? const <MatchedFoodRecommendations>[];

  List<MatchedFoodRecommendations> get displayedGroups => groups
      .map((MatchedFoodRecommendations group) {
        if (_selectedTab == MatchesRecommendationTab.restaurants) {
          final List<Restaurant> restaurants =
              _sortedRestaurants(group.restaurants)
                  .where((Restaurant value) {
                    final double? distance = value.distanceMetres;
                    return distance == null ||
                        distance <= radiusFor(group.food.id) * 1000;
                  })
                  .take(
                    _visibleRestaurantCount[group.food.id] ??
                        initialVisibleCount,
                  )
                  .toList(growable: false);
          return MatchedFoodRecommendations(
            food: group.food,
            restaurants: restaurants,
            submittedLandmarks: group.submittedLandmarks,
          );
        }
        final List<SubmittedLandmarkRecommendation> landmarks =
            _sortedLandmarks(group.submittedLandmarks)
                .where(
                  (SubmittedLandmarkRecommendation value) =>
                      !value.distanceMetres.isFinite ||
                      value.distanceMetres <= radiusFor(group.food.id) * 1000,
                )
                .take(
                  _visibleLandmarkCount[group.food.id] ?? initialVisibleCount,
                )
                .toList(growable: false);
        return MatchedFoodRecommendations(
          food: group.food,
          restaurants: group.restaurants,
          submittedLandmarks: landmarks,
        );
      })
      .toList(growable: false);

  int get displayedResultCount => displayedGroups.fold<int>(
    0,
    (int total, MatchedFoodRecommendations group) =>
        total +
        (_selectedTab == MatchesRecommendationTab.restaurants
            ? group.restaurants.length
            : group.submittedLandmarks.length),
  );

  bool canShowMore(int foodId) {
    final MatchedFoodRecommendations? group = _group(foodId);
    if (group == null) return false;
    final MatchedFoodRecommendations displayed = displayedGroups.firstWhere(
      (MatchedFoodRecommendations value) => value.food.id == foodId,
    );
    final int shown = _selectedTab == MatchesRecommendationTab.restaurants
        ? displayed.restaurants.length
        : displayed.submittedLandmarks.length;
    final int total = _selectedTab == MatchesRecommendationTab.restaurants
        ? group.restaurants.length
        : group.submittedLandmarks.length;
    return shown < total;
  }

  bool canShowLess(int foodId) =>
      _selectedTab == MatchesRecommendationTab.restaurants
      ? (_visibleRestaurantCount[foodId] ?? initialVisibleCount) >
                initialVisibleCount ||
            radiusFor(foodId) >
                (_initialRestaurantRadiusKm[foodId] ?? initialRadiusKm)
      : (_visibleLandmarkCount[foodId] ?? initialVisibleCount) >
                initialVisibleCount ||
            radiusFor(foodId) >
                (_initialLandmarkRadiusKm[foodId] ?? initialRadiusKm);

  @override
  Future<void> onInit() async {
    _request ??= MatchesRecommendationRequest(origin: locationFacade.latest);
    await loadRecommendations();
  }

  Future<void> loadRecommendations() => runGuarded(() async {
    _result = await discoveryLogic.getMatchesRecommendations(_request!);
    _initialiseGroupPaging();
  });

  void selectTab(MatchesRecommendationTab tab) {
    if (_selectedTab == tab) return;
    _selectedTab = tab;
    safeNotifyListeners();
  }

  void selectRestaurantSort(MatchesRestaurantSort sort) {
    if (_restaurantSort == sort) {
      _restaurantSortDirection = _toggled(_restaurantSortDirection);
    } else {
      _restaurantSort = sort;
      _restaurantSortDirection = MatchesSortDirection.ascending;
    }
    safeNotifyListeners();
  }

  void selectLandmarkSort(MatchesLandmarkSort sort) {
    if (_landmarkSort == sort) {
      _landmarkSortDirection = _toggled(_landmarkSortDirection);
    } else {
      _landmarkSort = sort;
      _landmarkSortDirection = MatchesSortDirection.ascending;
    }
    safeNotifyListeners();
  }

  Future<void> showMore(int foodId) async {
    if (_loadingGroupId != null || !canShowMore(foodId)) return;
    _loadingGroupId = foodId;
    safeNotifyListeners();
    try {
      if (_selectedTab == MatchesRecommendationTab.restaurants) {
        _restaurantRadiusKm[foodId] = _expandedRestaurantRadius(foodId);
        _visibleRestaurantCount[foodId] =
            (_visibleRestaurantCount[foodId] ?? initialVisibleCount) +
            additionalVisibleCount;
      } else {
        _landmarkRadiusKm[foodId] = _expandedLandmarkRadius(foodId);
        _visibleLandmarkCount[foodId] =
            (_visibleLandmarkCount[foodId] ?? initialVisibleCount) +
            additionalVisibleCount;
      }
    } finally {
      _loadingGroupId = null;
      safeNotifyListeners();
    }
  }

  void showLess(int foodId) {
    if (_selectedTab == MatchesRecommendationTab.restaurants) {
      _restaurantRadiusKm[foodId] =
          _initialRestaurantRadiusKm[foodId] ?? initialRadiusKm;
      _visibleRestaurantCount[foodId] = initialVisibleCount;
    } else {
      _landmarkRadiusKm[foodId] =
          _initialLandmarkRadiusKm[foodId] ?? initialRadiusKm;
      _visibleLandmarkCount[foodId] = initialVisibleCount;
    }
    safeNotifyListeners();
  }

  Future<void> removeMatchedFood(int foodId) => runGuarded(() async {
    final MatchesRecommendationResult? result = _result;
    final SwipeSession? session = result?.session;
    if (result == null || session == null) return;
    final SwipeSession updated = await discoveryLogic.removeMatchedFood(
      session,
      foodId,
    );
    _result = MatchesRecommendationResult(
      stateCode: result.stateCode,
      stateName: result.stateName,
      session: updated,
      groups: result.groups
          .where((MatchedFoodRecommendations group) => group.food.id != foodId)
          .toList(growable: false),
    );
    safeNotifyListeners();
  }, silent: true);

  double _expandedRestaurantRadius(int foodId) {
    final MatchedFoodRecommendations? group = _group(foodId);
    final double current = radiusFor(foodId);
    if (group == null) return current;
    final List<double> outside =
        group.restaurants
            .map((Restaurant value) => value.distanceMetres ?? double.infinity)
            .where((double value) => value.isFinite && value > current * 1000)
            .toList(growable: false)
          ..sort();
    return outside.isEmpty
        ? current
        : math.max(current, (outside.first / 1000).ceilToDouble());
  }

  double _expandedLandmarkRadius(int foodId) {
    final MatchedFoodRecommendations? group = _group(foodId);
    final double current = radiusFor(foodId);
    if (group == null) return current;
    final List<double> outside =
        group.submittedLandmarks
            .map(
              (SubmittedLandmarkRecommendation value) => value.distanceMetres,
            )
            .where((double value) => value.isFinite && value > current * 1000)
            .toList(growable: false)
          ..sort();
    return outside.isEmpty
        ? current
        : math.max(current, (outside.first / 1000).ceilToDouble());
  }

  void _initialiseGroupPaging() {
    final Set<int> activeFoodIds = groups
        .map((MatchedFoodRecommendations group) => group.food.id)
        .toSet();
    _removeMissingFoodIds(_restaurantRadiusKm, activeFoodIds);
    _removeMissingFoodIds(_landmarkRadiusKm, activeFoodIds);
    _removeMissingFoodIds(_initialRestaurantRadiusKm, activeFoodIds);
    _removeMissingFoodIds(_initialLandmarkRadiusKm, activeFoodIds);
    _removeMissingFoodIds(_visibleRestaurantCount, activeFoodIds);
    _removeMissingFoodIds(_visibleLandmarkCount, activeFoodIds);
    for (final MatchedFoodRecommendations group in groups) {
      final int foodId = group.food.id;
      final double restaurantRadius = _initialRadius(
        group.restaurants.map(
          (Restaurant value) => value.distanceMetres ?? double.infinity,
        ),
      );
      final double landmarkRadius = _initialRadius(
        group.submittedLandmarks.map(
          (SubmittedLandmarkRecommendation value) => value.distanceMetres,
        ),
      );
      _restaurantRadiusKm[foodId] = math.max(
        _restaurantRadiusKm[foodId] ?? restaurantRadius,
        restaurantRadius,
      );
      _landmarkRadiusKm[foodId] = math.max(
        _landmarkRadiusKm[foodId] ?? landmarkRadius,
        landmarkRadius,
      );
      _initialRestaurantRadiusKm[foodId] = restaurantRadius;
      _initialLandmarkRadiusKm[foodId] = landmarkRadius;
      _visibleRestaurantCount.putIfAbsent(foodId, () => initialVisibleCount);
      _visibleLandmarkCount.putIfAbsent(foodId, () => initialVisibleCount);
    }
  }

  void _removeMissingFoodIds<T>(Map<int, T> values, Set<int> activeFoodIds) {
    values.removeWhere((int foodId, T _) => !activeFoodIds.contains(foodId));
  }

  double _initialRadius(Iterable<double> distancesMetres) {
    final List<double> finite = distancesMetres
        .where((double value) => value.isFinite)
        .toList(growable: false);
    if (finite.isEmpty) return initialRadiusKm;
    return math.max(
      initialRadiusKm,
      (finite.reduce(math.min) / 1000).ceilToDouble(),
    );
  }

  MatchedFoodRecommendations? _group(int foodId) {
    for (final MatchedFoodRecommendations group in groups) {
      if (group.food.id == foodId) return group;
    }
    return null;
  }

  List<Restaurant> _sortedRestaurants(List<Restaurant> values) {
    final List<Restaurant> sorted = List<Restaurant>.of(values);
    sorted.sort((Restaurant first, Restaurant second) {
      final int comparison = switch (_restaurantSort) {
        MatchesRestaurantSort.distance => _compareNullable(
          first.distanceMetres,
          second.distanceMetres,
          _restaurantSortDirection,
        ),
        MatchesRestaurantSort.price => _compareNullable(
          _minimumPrice(first),
          _minimumPrice(second),
          _restaurantSortDirection,
        ),
        MatchesRestaurantSort.preference => _applyDirection(
          first.items.length.compareTo(second.items.length),
          _restaurantSortDirection,
        ),
        MatchesRestaurantSort.rating => _compareNullable(
          first.rating,
          second.rating,
          _restaurantSortDirection,
        ),
      };
      if (comparison != 0) return comparison;
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    return sorted;
  }

  List<SubmittedLandmarkRecommendation> _sortedLandmarks(
    List<SubmittedLandmarkRecommendation> values,
  ) {
    final List<SubmittedLandmarkRecommendation> sorted =
        List<SubmittedLandmarkRecommendation>.of(values);
    sorted.sort((
      SubmittedLandmarkRecommendation first,
      SubmittedLandmarkRecommendation second,
    ) {
      final int comparison = switch (_landmarkSort) {
        MatchesLandmarkSort.distance => _compareNullable(
          first.distanceMetres.isFinite ? first.distanceMetres : null,
          second.distanceMetres.isFinite ? second.distanceMetres : null,
          _landmarkSortDirection,
        ),
        MatchesLandmarkSort.name => first.name.toLowerCase().compareTo(
          second.name.toLowerCase(),
        ),
      };
      final int directed = _landmarkSort == MatchesLandmarkSort.distance
          ? comparison
          : _applyDirection(comparison, _landmarkSortDirection);
      if (directed != 0) return directed;
      return first.id.compareTo(second.id);
    });
    return sorted;
  }

  double? _minimumPrice(Restaurant restaurant) {
    final List<double> prices = restaurant.items
        .map((RestaurantItem item) => item.price)
        .whereType<double>()
        .toList(growable: false);
    if (prices.isEmpty) return null;
    return prices.reduce(math.min);
  }

  int _compareNullable(
    double? first,
    double? second,
    MatchesSortDirection direction,
  ) {
    // Unavailable values are always last. Reversing an ordinary
    // `null -> infinity` comparison would incorrectly put them first in a
    // descending sort.
    if (first == null && second == null) return 0;
    if (first == null) return 1;
    if (second == null) return -1;
    return _applyDirection(first.compareTo(second), direction);
  }

  int _applyDirection(int comparison, MatchesSortDirection direction) =>
      direction == MatchesSortDirection.ascending ? comparison : -comparison;

  MatchesSortDirection _toggled(MatchesSortDirection direction) =>
      direction == MatchesSortDirection.ascending
      ? MatchesSortDirection.descending
      : MatchesSortDirection.ascending;
}
