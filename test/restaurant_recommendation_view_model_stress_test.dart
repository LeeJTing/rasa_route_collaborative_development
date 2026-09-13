import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_recommendation_view_model.dart';

void main() {
  test('Quick Mode discards results from an older GPS fix', () async {
    const TouristLocation olderLocation = TouristLocation(
      latitude: 1.0,
      longitude: 103.0,
    );
    const TouristLocation latestLocation = TouristLocation(
      latitude: 2.0,
      longitude: 104.0,
    );
    final _FakeDiscoveryLogic logic = _FakeDiscoveryLogic();
    final RestaurantRecommendationViewModel viewModel = _TestViewModel(logic);
    addTearDown(viewModel.dispose);

    viewModel.onCurrentLocationChanged(olderLocation);
    await pumpEventQueue();
    viewModel.onCurrentLocationChanged(latestLocation);
    logic.complete(
      olderLocation,
      restaurants: <Restaurant>[_restaurant(1, 'Old GPS result')],
    );
    await pumpEventQueue(times: 20);
    logic.complete(
      latestLocation,
      restaurants: <Restaurant>[_restaurant(2, 'Latest GPS result')],
    );
    await pumpEventQueue(times: 20);

    expect(viewModel.restaurants.single.id, 2);
    expect(logic.requestedLatitudes, <double>[1.0, 2.0]);
  });
}

class _TestViewModel extends RestaurantRecommendationViewModel {
  _TestViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

class _FakeDiscoveryLogic extends DiscoveryLogicFacade {
  final Map<double, Completer<List<Restaurant>>> _restaurantResults =
      <double, Completer<List<Restaurant>>>{};
  final Map<double, Completer<List<SubmittedLandmarkRecommendation>>>
  _landmarkResults =
      <double, Completer<List<SubmittedLandmarkRecommendation>>>{};
  final List<double> requestedLatitudes = <double>[];

  @override
  Future<List<Restaurant>> getQuickModeRestaurants({
    required TouristLocation location,
    String? foodType,
  }) {
    requestedLatitudes.add(location.latitude);
    return _restaurantResults
        .putIfAbsent(location.latitude, Completer<List<Restaurant>>.new)
        .future;
  }

  @override
  Future<List<SubmittedLandmarkRecommendation>> getQuickModeLandmarks({
    required TouristLocation location,
    String? foodType,
  }) => _landmarkResults
      .putIfAbsent(
        location.latitude,
        Completer<List<SubmittedLandmarkRecommendation>>.new,
      )
      .future;

  void complete(
    TouristLocation location, {
    required List<Restaurant> restaurants,
  }) {
    _restaurantResults[location.latitude]!.complete(restaurants);
    _landmarkResults[location.latitude]!.complete(
      const <SubmittedLandmarkRecommendation>[],
    );
  }
}

Restaurant _restaurant(int id, String name) => Restaurant(
  id: id,
  name: name,
  category: 'Chinese',
  address: '',
  phone: '',
  website: '',
  openingHours: const [],
  distanceMetres: id * 100,
);
