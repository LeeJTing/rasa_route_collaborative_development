import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/location_data_model.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

void main() {
  group('AddLandmarkViewModel location rules (Malaysia + on land, A9)', () {
    test('allows an adjustment within 100m on Malaysian land', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      // Device fix in Kuala Lumpur.
      vm.onCurrentLocationChanged(
        LocationDataModel(
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
          LocationDataModel(
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
          LocationDataModel(
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

    test(
      'simulateLocation overrides the detected location and is reversible',
      () async {
        final AddLandmarkViewModel vm = AddLandmarkViewModel();
        await vm.onInit();
        // Real device GPS fix: Kuala Lumpur.
        vm.onCurrentLocationChanged(
          LocationDataModel(
            latitude: 3.1390,
            longitude: 101.6869,
            accuracyMeters: 10,
            capturedAt: DateTime.now(),
          ),
        );

        vm.simulateLocation(5.9804, 116.0735); // present as if in Kota Kinabalu

        expect(vm.isSimulatingLocation, isTrue);
        expect(vm.currentLocation.latitude, 5.9804);
        expect(vm.currentLocation.longitude, 116.0735);

        vm.useDeviceLocation(); // flip back to real GPS

        expect(vm.isSimulatingLocation, isFalse);
        expect(vm.currentLocation.latitude, 3.1390);
        vm.dispose();
      },
    );

    test('100m range is measured from the simulated location', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.onCurrentLocationChanged(
        LocationDataModel(
          latitude: 3.1390,
          longitude: 101.6869,
          accuracyMeters: 10,
          capturedAt: DateTime.now(),
        ),
      );
      vm.simulateLocation(5.9804, 116.0735); // simulate Kota Kinabalu

      // A pin ~60m from the simulated KK fix is allowed (it is on land).
      vm.adjustLandmarkLocation(5.9809, 116.0735);

      expect(vm.locationError, isNull);
      expect(vm.adjustedLocation.isKnown, isTrue);
      vm.dispose();
    });
  });
}
