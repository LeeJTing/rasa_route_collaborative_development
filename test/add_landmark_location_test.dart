import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

void main() {
  group('AddLandmarkViewModel location rules (Malaysia + on land, A9)', () {
    test('allows an adjustment within 100m on Malaysian land', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      // Device fix in Kuala Lumpur.
      vm.onCurrentLocationChanged(
        TouristLocation(
          latitude: 3.1390,
          longitude: 101.6869,
          accuracyMeters: 10,
          capturedAt: DateTime.now(),
        ),
      );

      vm.adjustLandmarkLocation(3.1395, 101.6870); // ~60m away, still in KL

      expect(vm.locationError, isNull);
      expect(vm.adjustedLocation.isKnown, isTrue);
      vm.dispose();
    });

    test(
      'rejects an adjustment that is within 100m but outside Malaysia',
      () async {
        final AddLandmarkViewModel vm = AddLandmarkViewModel();
        await vm.onInit();
        // Device fix is in Singapore (outside Malaysia) - the 100m check passes
        // but the Malaysia/land check must reject it.
        vm.onCurrentLocationChanged(
          TouristLocation(
            latitude: 1.3521,
            longitude: 103.8198,
            accuracyMeters: 10,
            capturedAt: DateTime.now(),
          ),
        );

        vm.adjustLandmarkLocation(1.3525, 103.8199); // ~45m away

        expect(vm.locationError, contains('Malaysia'));
        expect(
          vm.adjustedLocation.isKnown,
          isFalse,
        ); // reverted, nothing mutated
        vm.dispose();
      },
    );

    test(
      'rejects an adjustment that lands in the sea (Straits of Malacca)',
      () async {
        final AddLandmarkViewModel vm = AddLandmarkViewModel();
        await vm.onInit();
        // Device fix in the strait - adjusted pin stays in the strait.
        vm.onCurrentLocationChanged(
          TouristLocation(
            latitude: 3.0,
            longitude: 100.2,
            accuracyMeters: 10,
            capturedAt: DateTime.now(),
          ),
        );

        vm.adjustLandmarkLocation(3.0005, 100.2);

        expect(vm.locationError, contains('Malaysia'));
        expect(vm.adjustedLocation.isKnown, isFalse);
        vm.dispose();
      },
    );

    test('blocks submit while the fix is at sea / outside Malaysia', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      // "At sea" mock preset - Straits of Malacca.
      vm.onCurrentLocationChanged(
        TouristLocation(
          latitude: 3.0,
          longitude: 100.2,
          accuracyMeters: 10,
          capturedAt: DateTime.now(),
        ),
      );

      expect(vm.isAddLocationBlocked, isTrue);
      expect(vm.addLocationBlockMessage, isNotNull);
      // The Submit bar is disabled with the location as the reason - even
      // before any form field is filled in, the form can never be submitted.
      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Malaysian land'));
      vm.dispose();
    });

    test('a fix on Malaysian land does not block the form', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.onCurrentLocationChanged(
        TouristLocation(
          latitude: 3.1390,
          longitude: 101.6869,
          accuracyMeters: 10,
          capturedAt: DateTime.now(),
        ),
      );

      expect(vm.isAddLocationBlocked, isFalse);
      expect(vm.addLocationBlockMessage, isNull);
      vm.dispose();
    });
  });

  group('each capture keeps its OWN location', () {
    test('first food, second food and the signboard photo differ', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();

      // The first food is captured at KL - the form's landmark location.
      vm.setRecognizedFood(
        _food('Murtabak'),
        captureLocation: _fix(3.1390, 101.6869),
      );
      expect(vm.captureLocation.latitude, closeTo(3.1390, 0.00001));
      expect(vm.baseLocation.latitude, closeTo(3.1390, 0.00001));

      // The second food, ~20 m north, keeps its own fix in the list.
      vm.addAdditionalFood(
        _food('Roti Canai'),
        captureLocation: _fix(3.1392, 101.6869),
      );
      expect(vm.additionalFoods.length, 1);
      expect(
        vm.additionalFoods.single.captureLocation.latitude,
        closeTo(3.1392, 0.00001),
      );
      // ...and it must not overwrite the first food's fix.
      expect(vm.captureLocation.latitude, closeTo(3.1390, 0.00001));

      // The signboard/stall photo has its OWN getter too.
      expect(vm.capturedImageLocation.isKnown, isFalse);
      vm.setCapturedImage(
        _image(),
        'signboard',
        captureLocation: _fix(3.1395, 101.6869),
      );
      expect(vm.capturedImageLocation.latitude, closeTo(3.1395, 0.00001));

      // Clearing the photo drops its fix with it - the foods keep theirs.
      vm.clearCapturedImage();
      expect(vm.capturedImageLocation.isKnown, isFalse);
      expect(vm.captureLocation.latitude, closeTo(3.1390, 0.00001));
      expect(
        vm.additionalFoods.single.captureLocation.latitude,
        closeTo(3.1392, 0.00001),
      );
      vm.dispose();
    });
  });
}

/// A known GPS fix for the per-capture location tests.
TouristLocation _fix(double latitude, double longitude) => TouristLocation(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: 5,
  capturedAt: DateTime.now(),
);

XFile _image() => XFile.fromData(
  Uint8List.fromList(<int>[1, 2, 3]),
  mimeType: 'image/jpeg',
  name: 'test.jpg',
);

/// Distinct catalogue ids per dish - the form's duplicate guard treats two
/// foods with the same id as the same dish, so the fixtures must differ.
const Map<String, int> _foodIds = <String, int>{'Murtabak': 1, 'Roti Canai': 2};

LocalFood _food(String name) => LocalFood(
  id: _foodIds[name] ?? 3,
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
