import '../../domain_model/tourist_location.dart';
import '../../external/location/mock_location_service.dart';
import '../../model/data_models/location_data_model.dart';
import '../../shared_client/device_capability_manager/device_capability_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';

/// Where the tourist is: permissions, fixes and the cached last position.
///
/// A repository is the only layer that talks to the shared clients, and the
/// only place a data model and a domain model meet. `DeviceCapabilityManager`
/// hands back `LocationDataModel`; everything above this class gets
/// [TouristLocation] instead, so no ViewModel or View ever imports a data
/// model.
class LocationRepository {
  LocationRepository();

  final DeviceCapabilityManager device = DeviceCapabilityManager();
  final LocalStorageManager storage = LocalStorageManager();
  final MockLocationService mock = MockLocationService();

  /// One GPS fix (see `DeviceCapabilityManager.currentLocation`).
  ///
  /// While a dev GPS mock is live this returns the mocked spot instead, so
  /// every consumer (the background monitor, Find Me, ...) agrees on the same
  /// location for as long as the mock is active.
  ///
  /// Right after a mock STOPS the fix is asked from the platform location
  /// manager instead: Android's fused provider can keep answering with the
  /// mocked spot as if it were real, which left "Stop mock" still behaving
  /// like the mock was on (a capture taken at the tourist's real spot was
  /// measured against the mocked one and rejected as > 50 m away). The mock
  /// only ever touched the platform's TEST provider, so the platform's own
  /// fix is the one that can be trusted. Best-effort: a platform fix that
  /// does not arrive falls back to the normal call (see
  /// `DeviceCapabilityManager.currentLocation`).
  Future<TouristLocation> currentLocation() async {
    if (mock.isActive) return mockLocation ?? TouristLocation.unknown;
    final DateTime? stoppedAt = mock.stoppedAt;
    final bool justStopped =
        stoppedAt != null &&
        DateTime.now().difference(stoppedAt) < postMockTrustWindow;
    return _toDomain(
      await device.currentLocation(preferPlatformProvider: justStopped),
    );
  }

  /// How long after a mock stops the platform provider is preferred - the
  /// fused provider's cached mock can outlive the mock itself by a while.
  static const Duration postMockTrustWindow = Duration(minutes: 2);

  /// Continuous GPS fixes, consumed by `LocationMonitor`.
  Stream<TouristLocation> locationStream({
    Duration interval = const Duration(seconds: 30),
  }) => device.locationStream(interval: interval).map(_toDomain);

  /// True when the OS location permission is granted (asked for it if not).
  Future<bool> ensureLocationPermission() => device.requestLocationPermission();

  /// Whether the OS location service is switched on right now.
  Future<bool> isLocationServiceEnabled() => device.isLocationServiceEnabled();

  /// Fires when the tourist turns location on or off in system settings.
  Stream<bool> locationServiceStream() => device.locationServiceStream();

  // --- dev GPS mock (Android-only presenter tool) --------------------------

  /// Whether this build can mock the OS GPS (Android, non-web). Views hide
  /// the dev control when false.
  bool get mockSupported => MockLocationService.isSupported;

  /// Whether a mock is live right now.
  bool get mockActive => mock.isActive;

  /// The mocked spot as a [TouristLocation], or null when no mock is live.
  TouristLocation? get mockLocation {
    final double? latitude = mock.latitude;
    final double? longitude = mock.longitude;
    if (latitude == null || longitude == null) return null;
    return TouristLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: 5,
    );
  }

  /// Fires `true` the moment a mock starts and `false` the moment it stops.
  /// `LocationMonitor` listens so it can hold the mock and stop trusting the
  /// real GPS, then resume real fixes when the mock is stopped.
  Stream<bool> mockActiveChanges() => mock.activeChanges;

  /// Teleports the OS GPS to [latitude]/[longitude] (dev tool). Returns an
  /// error message, or null on success.
  Future<String?> setMockLocation(double latitude, double longitude) =>
      mock.setMockLocation(latitude, longitude);

  /// Stops mocking and lets real GPS fixes flow again.
  Future<void> stopMockLocation() => mock.stopMockLocation();

  /// Data model -> domain model. The only crossing point.
  static TouristLocation _toDomain(LocationDataModel data) => TouristLocation(
    latitude: data.latitude,
    longitude: data.longitude,
    accuracyMeters: data.accuracyMeters,
    capturedAt: data.capturedAt,
  );
}
