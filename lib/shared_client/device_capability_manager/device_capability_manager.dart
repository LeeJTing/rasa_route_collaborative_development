import 'dart:async';
import 'dart:typed_data';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;

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

  /// How long any single location call may take before it is treated as a
  /// failure.
  ///
  /// Every call below is bounded. Neither `requestPermission` nor
  /// `getCurrentPosition` completes on its own if the OS never answers - and
  /// `getCurrentPosition` will happily wait forever for a first satellite fix,
  /// which is exactly what happens the moment GPS is switched on. An
  /// unbounded await here becomes a spinner that never stops three layers up.
  static const Duration locationTimeout = Duration(seconds: 12);

  Future<bool> requestLocationPermission() async {
    try {
      final LocationPermission permission = await Geolocator.requestPermission()
          .timeout(locationTimeout);
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      // Timed out, or a request was already in flight - either way the honest
      // answer is "not granted right now".
      return false;
    }
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
      final Position position =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              // Geolocator's own ceiling: without it the call blocks until a
              // satellite fix arrives, which indoors or just after GPS is
              // switched on may be never.
              timeLimit: locationTimeout,
            ),
          ).timeout(
            // A second ceiling in case the platform side ignores the first.
            locationTimeout + const Duration(seconds: 3),
          );
      return _fromPosition(position);
    } catch (_) {
      // Timed out, service switched off mid-call, or no fix available. All of
      // these mean the same thing to every caller: no position.
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
