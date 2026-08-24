import '../../domain_model/tourist_location.dart';
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

  /// One GPS fix (see `DeviceCapabilityManager.currentLocation`).
  Future<TouristLocation> currentLocation() async =>
      _toDomain(await device.currentLocation());

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

  /// Data model -> domain model. The only crossing point.
  static TouristLocation _toDomain(LocationDataModel data) => TouristLocation(
    latitude: data.latitude,
    longitude: data.longitude,
    accuracyMeters: data.accuracyMeters,
    capturedAt: data.capturedAt,
  );
}
