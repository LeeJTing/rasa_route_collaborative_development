import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

/// KL fix used as the submitted landmark's location in every test.
const double _lat = 3.1390;
const double _lon = 101.6869;

Restaurant _restaurant(int id, double? lat, double? lon) => Restaurant(
  id: id,
  name: 'Same Kopitiam',
  category: 'Kopitiam',
  address: '',
  latitude: lat,
  longitude: lon,
  phone: '',
  website: '',
  openingHours: const <OpeningHour>[],
);

SubmittedLandmark _landmark(int id, double? lat, double? lon) =>
    SubmittedLandmark(
      id: id,
      name: 'Same Kopitiam',
      latitude: lat,
      longitude: lon,
      category: '',
      reportedCount: 0,
      status: LandmarkStatus.available,
      items: const <LandmarkItem>[],
      openingHours: const <OpeningHour>[],
    );

void main() {
  group('nearestRestaurantWithinMetres (A13 restaurant merge)', () {
    test('returns the nearest restaurant within 100m of the submission', () {
      // ~0m, ~55m, and ~220m away (0.0005 lat ~= 55m; 0.0020 ~= 220m).
      final List<Restaurant> candidates = <Restaurant>[
        _restaurant(1, _lat + 0.0020, _lon), // too far
        _restaurant(2, _lat, _lon), // exact same spot
        _restaurant(3, _lat + 0.0005, _lon), // ~55m
      ];
      expect(
        LandmarkSubmissionLogic.nearestRestaurantWithinMetres(
          candidates,
          _lat,
          _lon,
        )?.id,
        2,
      );
    });

    test('ignores candidates that have no coordinates', () {
      final List<Restaurant> candidates = <Restaurant>[
        _restaurant(1, null, null),
        _restaurant(2, _lat + 0.0005, _lon),
      ];
      expect(
        LandmarkSubmissionLogic.nearestRestaurantWithinMetres(
          candidates,
          _lat,
          _lon,
        )?.id,
        2,
      );
    });

    test('returns null when every match is beyond 100m (different town)', () {
      final List<Restaurant> candidates = <Restaurant>[
        _restaurant(1, _lat + 0.01, _lon), // ~1.1km
        _restaurant(2, _lat - 0.02, _lon), // ~2.2km
      ];
      expect(
        LandmarkSubmissionLogic.nearestRestaurantWithinMetres(
          candidates,
          _lat,
          _lon,
        ),
        isNull,
      );
    });

    test('returns null for an empty candidate list', () {
      expect(
        LandmarkSubmissionLogic.nearestRestaurantWithinMetres(
          const <Restaurant>[],
          _lat,
          _lon,
        ),
        isNull,
      );
    });
  });

  group('nearestLandmarkWithinMetres (A13 submitted-landmark merge)', () {
    test('picks the nearest submitted landmark within 100m', () {
      final List<SubmittedLandmark> candidates = <SubmittedLandmark>[
        _landmark(1, _lat + 0.0005, _lon), // ~55m
        _landmark(2, _lat + 0.0020, _lon), // ~220m - too far
        _landmark(3, _lat, _lon), // exact same spot
      ];
      expect(
        LandmarkSubmissionLogic.nearestLandmarkWithinMetres(
          candidates,
          _lat,
          _lon,
        )?.id,
        3,
      );
    });

    test('returns null when all submitted landmarks are beyond 100m', () {
      final List<SubmittedLandmark> candidates = <SubmittedLandmark>[
        _landmark(1, _lat + 0.01, _lon),
        _landmark(2, _lat - 0.03, _lon),
      ];
      expect(
        LandmarkSubmissionLogic.nearestLandmarkWithinMetres(
          candidates,
          _lat,
          _lon,
        ),
        isNull,
      );
    });
  });

  group('LandmarkSubmitResult', () {
    test('created outcome is not merged and carries the landmark id', () {
      const LandmarkSubmitResult result = LandmarkSubmitResult.created(
        landmarkId: 42,
      );
      expect(result.merged, isFalse);
      expect(result.landmarkId, 42);
      expect(result.restaurantId, isNull);
      expect(result.targetName, isNull);
      expect(result.addedDishNames, isEmpty);
      expect(result.existingDishNames, isEmpty);
    });

    test('merged-into-restaurant outcome is merged with a target name', () {
      const LandmarkSubmitResult result =
          LandmarkSubmitResult.mergedIntoRestaurant(
            restaurantId: 7,
            targetName: 'Restoran ABC',
          );
      expect(result.merged, isTrue);
      expect(result.restaurantId, 7);
      expect(result.landmarkId, isNull);
      expect(result.targetName, 'Restoran ABC');
    });

    test('merged-into-landmark outcome is merged with a target name', () {
      const LandmarkSubmitResult result =
          LandmarkSubmitResult.mergedIntoLandmark(
            landmarkId: 9,
            targetName: 'Otai',
          );
      expect(result.merged, isTrue);
      expect(result.landmarkId, 9);
      expect(result.restaurantId, isNull);
      expect(result.targetName, 'Otai');
    });

    test('copyWith fills the dish-level added/existing detail', () {
      const LandmarkSubmitResult base =
          LandmarkSubmitResult.mergedIntoRestaurant(
            restaurantId: 7,
            targetName: 'Restoran ABC',
          );
      final LandmarkSubmitResult result = base.copyWith(
        addedDishNames: const <String>['Satay'],
        existingDishNames: const <String>['Nasi Lemak'],
      );
      expect(result.merged, isTrue);
      expect(result.restaurantId, 7);
      expect(result.addedDishNames, <String>['Satay']);
      expect(result.existingDishNames, <String>['Nasi Lemak']);
    });
  });
}
