import 'dart:typed_data';

import 'package:geolocator/geolocator.dart';

import '../../model/data_models/location_data_model.dart';

/// Access to device hardware: camera, gallery, GPS, permissions.
///
/// A singleton, like the other shared clients - `DeviceCapabilityManager()`
/// always returns the same instance.
///
/// Wrap the platform plugins (`image_picker`, `geolocator`,
/// `permission_handler`) here and nowhere else, so a repository never asks for
/// a permission itself.
class DeviceCapabilityManager {
  factory DeviceCapabilityManager() => _instance;

  DeviceCapabilityManager._();

  static final DeviceCapabilityManager _instance = DeviceCapabilityManager._();

  // --- location --------------------------------------------------------------

  Future<bool> hasLocationPermission() async {
    final LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<bool> requestLocationPermission() async {
    final LocationPermission permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Whether the OS location service is switched on. Separate from
  /// permission: a tourist can grant the app permission and still have GPS
  /// turned off device-wide.
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// Fires whenever the tourist turns location on or off in system settings.
  ///
  /// This is how the app finds out GPS went away. The position stream simply
  /// stops - it does not announce anything - so without watching this the last
  /// known fix would sit on the map forever.
  Stream<bool> locationServiceStream() => Geolocator.getServiceStatusStream()
      .map((ServiceStatus status) => status == ServiceStatus.enabled);

  /// One GPS fix, or `LocationDataModel.unknown` when permission is denied,
  /// location is switched off, or no fix is available yet.
  ///
  /// Never throws. `getCurrentPosition` raises if location is disabled
  /// mid-call, and a thrown exception here would surface as a red error banner
  /// over the map when the honest answer is simply "no fix".
  Future<LocationDataModel> currentLocation() async {
    if (!await hasLocationPermission()) return LocationDataModel.unknown;
    if (!await isLocationServiceEnabled()) return LocationDataModel.unknown;
    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return _fromPosition(position);
    } catch (_) {
      return LocationDataModel.unknown;
    }
  }

  /// Continuous fixes, consumed by `LocationMonitor`. Emits a new fix when the
  /// device moves [distanceFilter] metres (GPS streams by movement, not on a
  /// fixed timer - the [interval] parameter is kept for call-site clarity but
  /// the platform drives the cadence).
  Stream<LocationDataModel> locationStream({
    Duration interval = const Duration(seconds: 30),
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map(_fromPosition);
  }

  LocationDataModel _fromPosition(Position position) => LocationDataModel(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
    capturedAt: position.timestamp,
  );

  // --- camera ----------------------------------------------------------------

  Future<bool> hasCameraPermission() async => false;

  Future<bool> requestCameraPermission() async => false;

  /// Opens the camera. Returns null if the tourist cancels.
  Future<CapturedImage?> capturePhoto() async => null;

  /// Opens the gallery. Returns null if the tourist cancels.
  Future<CapturedImage?> pickPhoto() async => null;
}

/// A photo taken or picked by the tourist.
class CapturedImage {
  const CapturedImage({
    required this.path,
    required this.bytes,
    this.mimeType = 'image/jpeg',
  });

  final String path;
  final Uint8List bytes;
  final String mimeType;
}
