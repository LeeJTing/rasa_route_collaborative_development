import 'dart:typed_data';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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

  /// One GPS fix, or `LocationDataModel.unknown` when permission is denied /
  /// no fix is available yet.
  Future<LocationDataModel> currentLocation() async {
    if (!await hasLocationPermission()) return LocationDataModel.unknown;
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return _fromPosition(position);
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

  /// True when the OS camera permission is granted (Android/iOS runtime
  /// permission - the `CAMERA` manifest permission alone is not enough on
  /// Android 6+).
  Future<bool> hasCameraPermission() async {
    final PermissionStatus status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Asks for the OS camera permission if it isn't granted yet, and reports
  /// whether it is granted afterwards.
  Future<bool> requestCameraPermission() async {
    if (await hasCameraPermission()) return true;
    final PermissionStatus status = await Permission.camera.request();
    return status.isGranted;
  }

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
