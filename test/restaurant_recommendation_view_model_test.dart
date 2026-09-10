import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_recommendation_view_model.dart';

/// Exercises the REAL background-reload throttle in
/// [RestaurantRecommendationViewModel] - the 30 s cooldown, the in-flight
/// guard and the single trailing reload - without a network.
///
/// The two seams production uses are overridden:
/// [RestaurantRecommendationViewModel.createDiscoveryLogic] supplies a facade
/// that counts downloads, and
/// [RestaurantRecommendationViewModel.currentTime] supplies a controllable
/// clock so the cooldown can be aged without waiting thirty real seconds.
class _FakeDiscoveryFacade extends DiscoveryLogicFacade {
  int restaurantCalls = 0;
  int landmarkCalls = 0;

  /// The location handed to each getQuickModeRestaurants call - lets a test
  /// assert the reload used the newest fix, not a stale one.
  final List<TouristLocation> observedLocations = <TouristLocation>[];

  /// When non-null, the NEXT restaurant call waits on this before returning,
  /// so a test can hold a reload in flight (the in-flight / queue races).
  Completer<void>? gateNextRestaurantCall;

  @override
  Future<List<Restaurant>> getQuickModeRestaurants({
    required TouristLocation location,
  }) async {
    restaurantCalls++;
    observedLocations.add(location);
    final Completer<void>? gate = gateNextRestaurantCall;
    if (gate != null) {
      gateNextRestaurantCall = null;
      await gate.future;
    }
    return const <Restaurant>[];
  }

  @override
  Future<List<SubmittedLandmarkRecommendation>> getQuickModeLandmarks({
    required TouristLocation location,
  }) async {
    landmarkCalls++;
    return const <SubmittedLandmarkRecommendation>[];
  }
}

class _TestRestaurantRecommendationViewModel
    extends RestaurantRecommendationViewModel {
  _TestRestaurantRecommendationViewModel(
    this.fakeFacade, {
    required DateTime startTime,
  }) : _now = startTime;

  final DiscoveryLogicFacade fakeFacade;
  DateTime _now;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => fakeFacade;

  @override
  DateTime currentTime() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

TouristLocation _at(double latitude, double longitude) =>
    TouristLocation(latitude: latitude, longitude: longitude);

/// Flushes the microtask chain a fire-and-forget background reload leaves
/// behind (runGuarded -> future completion -> trailing reload).
Future<void> _settle() => pumpEventQueue();

void main() {
  group('Quick Mode background reload throttle', () {
    test('a GPS fix triggers a reload', () async {
      final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
      final _TestRestaurantRecommendationViewModel viewModel =
          _TestRestaurantRecommendationViewModel(
            facade,
            startTime: DateTime(2026, 9, 10, 12),
          );

      viewModel.onCurrentLocationChanged(_at(3.1, 101.6));
      await _settle();

      expect(facade.restaurantCalls, 1);
      expect(facade.landmarkCalls, 1);
    });

    test('a second GPS fix inside the 30s cooldown is skipped', () async {
      final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
      final _TestRestaurantRecommendationViewModel viewModel =
          _TestRestaurantRecommendationViewModel(
            facade,
            startTime: DateTime(2026, 9, 10, 12),
          );

      viewModel.onCurrentLocationChanged(_at(3.1, 101.6));
      await _settle();
      expect(facade.restaurantCalls, 1);

      // A fix 10 s later - still inside the cooldown.
      viewModel.advance(const Duration(seconds: 10));
      viewModel.onCurrentLocationChanged(_at(3.2, 101.7));
      await _settle();

      expect(
        facade.restaurantCalls,
        1,
        reason: 'fixes inside the 30s cooldown must not reload',
      );
    });

    test(
      'a GPS fix after the cooldown reloads with the newest location',
      () async {
        final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
        final _TestRestaurantRecommendationViewModel viewModel =
            _TestRestaurantRecommendationViewModel(
              facade,
              startTime: DateTime(2026, 9, 10, 12),
            );

        viewModel.onCurrentLocationChanged(_at(3.1, 101.6));
        await _settle();

        // Ignored fix inside the cooldown - but it is the newest position.
        viewModel.advance(const Duration(seconds: 10));
        viewModel.onCurrentLocationChanged(_at(3.2, 101.7));
        await _settle();

        // First fix AFTER the cooldown - must reload, using the newest fix.
        viewModel.advance(
          const Duration(seconds: 25),
        ); // 35s since first reload
        viewModel.onCurrentLocationChanged(_at(3.3, 101.8));
        await _settle();

        expect(facade.restaurantCalls, 2);
        expect(facade.observedLocations.last.latitude, 3.3);
        expect(facade.observedLocations.last.longitude, 101.8);
      },
    );

    test('a monitor notification is throttled by the same cooldown', () async {
      final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
      final _TestRestaurantRecommendationViewModel viewModel =
          _TestRestaurantRecommendationViewModel(
            facade,
            startTime: DateTime(2026, 9, 10, 12),
          );

      // The monitor notifies (new data landed elsewhere)...
      viewModel.onNearbyRestaurantsUpdated(const <Restaurant>[]);
      await _settle();
      expect(facade.restaurantCalls, 1);

      // ...and again 10 s later, inside the cooldown.
      viewModel.advance(const Duration(seconds: 10));
      viewModel.onNearbyRestaurantsUpdated(const <Restaurant>[]);
      await _settle();

      expect(
        facade.restaurantCalls,
        1,
        reason: 'monitor notifications share the GPS-fix cooldown',
      );
    });

    test('a manual loadNearbyRestaurants bypasses the cooldown', () async {
      final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
      final _TestRestaurantRecommendationViewModel viewModel =
          _TestRestaurantRecommendationViewModel(
            facade,
            startTime: DateTime(2026, 9, 10, 12),
          );

      // A background fix starts the cooldown...
      viewModel.onCurrentLocationChanged(_at(3.1, 101.6));
      await _settle();
      expect(facade.restaurantCalls, 1);

      // ...but the View's Retry button / onInit call this directly, and a
      // user asking for a reload must always get one.
      viewModel.advance(const Duration(seconds: 5));
      await viewModel.loadNearbyRestaurants();

      expect(
        facade.restaurantCalls,
        2,
        reason: 'an explicit load must ignore the background cooldown',
      );
    });

    test('a fix arriving while a reload is in flight queues exactly one '
        'trailing reload', () async {
      final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
      final _TestRestaurantRecommendationViewModel viewModel =
          _TestRestaurantRecommendationViewModel(
            facade,
            startTime: DateTime(2026, 9, 10, 12),
          );
      final Completer<void> gate = Completer<void>();
      facade.gateNextRestaurantCall = gate;

      // First reload starts and is held in flight by the gate.
      viewModel.onCurrentLocationChanged(_at(3.1, 101.6));
      expect(facade.restaurantCalls, 1);

      // Fixes arrive while it is still out (past the cooldown).
      viewModel.advance(const Duration(seconds: 31));
      viewModel.onCurrentLocationChanged(_at(3.2, 101.7));
      viewModel.advance(const Duration(seconds: 2));
      viewModel.onCurrentLocationChanged(_at(3.3, 101.8));
      expect(
        facade.restaurantCalls,
        1,
        reason: 'fixes must not stack behind the in-flight reload',
      );

      // The held reload finishes; the queued change runs once.
      gate.complete();
      await _settle();

      expect(
        facade.restaurantCalls,
        2,
        reason: 'several mid-flight fixes collapse to ONE trailing reload',
      );
      // The trailing reload uses the newest fix, not the first one.
      expect(facade.observedLocations.last.latitude, 3.3);
      expect(facade.observedLocations.last.longitude, 101.8);
    });

    test('onInit performs the initial load immediately and once', () async {
      final _FakeDiscoveryFacade facade = _FakeDiscoveryFacade();
      final _TestRestaurantRecommendationViewModel viewModel =
          _TestRestaurantRecommendationViewModel(
            facade,
            startTime: DateTime(2026, 9, 10, 12),
          );

      await viewModel.onInit();

      expect(facade.restaurantCalls, 1);
      expect(facade.landmarkCalls, 1);

      viewModel.dispose();
    });
  });
}
