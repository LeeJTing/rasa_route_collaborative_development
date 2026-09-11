import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/exploration_filter.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/map.dart';
import 'package:rasa_route_collaborative_development/domain_model/region.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_mode.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/dashboard_view_model.dart';

void main() {
  test(
    'food camera focus refreshes pins without replacing the active state session',
    () async {
      const TouristLocation deviceLocation = TouristLocation(
        latitude: 5.4141,
        longitude: 100.3288,
      );
      DashboardViewModel.onCurrentLocationChanged(deviceLocation);
      final _FakeDiscoveryLogicFacade logic = _FakeDiscoveryLogicFacade();
      final DashboardViewModel viewModel = _TestDashboardViewModel(logic);
      addTearDown(() {
        viewModel.dispose();
        DashboardViewModel.onCurrentLocationChanged(TouristLocation.unknown);
      });

      viewModel.onCameraChanged(
        latitude: 3.1,
        longitude: 101.6,
        zoom: DiscoveryLogicFacade.swipeFoodFocusZoom,
        south: 3,
        west: 101.5,
        north: 3.2,
        east: 101.7,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(logic.prepareCount, 1);
      expect(logic.lastDistanceOrigin, deviceLocation);
      expect(viewModel.matchesRecommendationRequest.origin, deviceLocation);

      viewModel.toggleSwipePanel();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // The selected food moves the map to an occurrence over the state line.
      viewModel.onCameraChanged(
        latitude: 3.2,
        longitude: 101.8,
        zoom: DiscoveryLogicFacade.swipeFoodFocusZoom,
        south: 3.1,
        west: 101.7,
        north: 3.3,
        east: 101.9,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(logic.prepareCount, 1);
      expect(viewModel.swipeStateName, 'Kuala Lumpur');
      expect(viewModel.showSwipeResumePrompt, isFalse);
      expect(viewModel.currentSwipeFood?.id, 1);
      expect(viewModel.minimumZoom, DiscoveryLogicFacade.detailedViewZoom);

      final int pinLoadsBeforePan = logic.pinLoadCount;
      viewModel.onCameraChanged(
        latitude: 3.201,
        longitude: 101.801,
        zoom: DiscoveryLogicFacade.swipeFoodFocusZoom,
        south: 3.101,
        west: 101.701,
        north: 3.301,
        east: 101.901,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));

      // Even a small manual pan refreshes the food-filtered viewport without
      // changing the state-scoped deck or reopening its resume prompt.
      expect(logic.pinLoadCount, greaterThan(pinLoadsBeforePan));
      expect(logic.lastPinFoodId, 1);
      expect(logic.prepareCount, 1);
      expect(viewModel.swipeStateName, 'Kuala Lumpur');
      expect(viewModel.showSwipeResumePrompt, isFalse);

      expect(viewModel.matchesCount, 1);
      await viewModel.refreshSwipeSessionAfterMatches();
      expect(viewModel.matchesCount, 0);

      await viewModel.refreshSwipeQueueAfterProfileChange();
      expect(logic.profileRefreshCount, 1);
      expect(viewModel.currentSwipeFoodRestricted, isTrue);
      expect(viewModel.showSwipeResumePrompt, isFalse);
    },
  );
}

class _TestDashboardViewModel extends DashboardViewModel {
  _TestDashboardViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

class _FakeDiscoveryLogicFacade extends DiscoveryLogicFacade {
  int prepareCount = 0;
  int pinLoadCount = 0;
  int? lastPinFoodId;
  TouristLocation? lastDistanceOrigin;
  int profileRefreshCount = 0;

  static const LocalFood _food = LocalFood(
    id: 1,
    name: 'Nasi Lemak',
    description: '',
    origin: 'Malaysia',
    culturalBackground: '',
    ingredients: '',
    category: 'Malay',
    cookingStyle: '',
    mealType: 'All Day',
    foodType: 'Food',
  );

  static const SwipeSession _session = SwipeSession(
    sessionId: 'session-kul',
    touristId: 'tourist-1',
    stateCode: 'KUL',
    candidateFoodIds: <int>[1],
    likedFoodIds: <int>[1],
    dislikedFoodIds: <int>[],
  );

  @override
  Future<SwipeModePreparation> prepareSwipeMode({
    required double latitude,
    required double longitude,
    TouristLocation distanceOrigin = TouristLocation.unknown,
  }) async {
    prepareCount++;
    lastDistanceOrigin = distanceOrigin;
    return SwipeModePreparation(
      stateCode: prepareCount == 1 ? 'KUL' : 'SGR',
      stateName: prepareCount == 1 ? 'Kuala Lumpur' : 'Selangor',
      touristId: 'tourist-1',
      queue: const <LocalFood>[_food],
      restrictedFoodIds: const <int>{},
      savedSession: prepareCount == 1 ? null : _session,
      savedRestaurantCount: 0,
    );
  }

  @override
  Future<SwipeSession> startNewSwipeSession(
    SwipeModePreparation preparation,
  ) async => _session;

  @override
  Future<SwipeModePreparation> refreshSwipeModeAfterProfileChange({
    required double latitude,
    required double longitude,
    TouristLocation distanceOrigin = TouristLocation.unknown,
  }) async {
    profileRefreshCount++;
    return SwipeModePreparation(
      stateCode: 'KUL',
      stateName: 'Kuala Lumpur',
      touristId: 'tourist-1',
      queue: const <LocalFood>[_food],
      restrictedFoodIds: const <int>{1},
      savedSession: _session.copyWith(likedFoodIds: const <int>[]),
      savedRestaurantCount: 0,
    );
  }

  @override
  Future<SwipeSession?> reloadSwipeSession(
    SwipeModePreparation preparation,
  ) async => _session.copyWith(likedFoodIds: const <int>[]);

  @override
  Future<GeoPoint?> nearestFoodLocation({
    required int localFoodId,
    required double fromLatitude,
    required double fromLongitude,
  }) async => const GeoPoint(3.2, 101.8);

  @override
  Future<Region?> regionAt(double latitude, double longitude) async =>
      const Region(
        code: 'SGR',
        name: 'Selangor',
        centreLatitude: 3.2,
        centreLongitude: 101.8,
        defaultZoom: 13,
        boundary: <GeoPoint>[],
        places: <RegionPlace>[],
      );

  @override
  Future<MapPinPage> mapPins({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
    double? south,
    double? west,
    double? north,
    double? east,
    double? fromLatitude,
    double? fromLongitude,
    double zoom = DiscoveryLogicFacade.detailedViewZoom,
    int? limit,
  }) async {
    pinLoadCount++;
    lastPinFoodId = localFoodId;
    return MapPinPage.empty;
  }
}
