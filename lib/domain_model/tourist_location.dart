/// Where the tourist is (REQ102_7).
///
/// The domain counterpart of `LocationDataModel`. They carry the same fields;
/// the difference is who is allowed to hold them. `LocationDataModel` is the
/// wire shape `DeviceCapabilityManager` produces and local storage caches, so
/// it stops at `LocationRepository` - the one place a data model and a domain
/// model are allowed to meet. Everything above the repository, up through the
/// logic classes, the ViewModel facade, the ViewModels and the Views, speaks
/// [TouristLocation].
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class TouristLocation {
  const TouristLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.capturedAt,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy reported by the platform, in metres.
  final double? accuracyMeters;

  /// When the fix was taken. Used to decide whether a cached fix is stale.
  final DateTime? capturedAt;

  /// Before the first fix arrives, and whenever permission is refused.
  ///
  /// A sentinel rather than a null so every caller has something to hold;
  /// [isKnown] is what they check.
  static const TouristLocation unknown = TouristLocation(
    latitude: 0,
    longitude: 0,
  );

  /// Null Island is in the Gulf of Guinea, so 0,0 is never a real Malaysian
  /// fix - it always means "no fix yet".
  bool get isKnown => latitude != 0 || longitude != 0;

  @override
  String toString() =>
      'TouristLocation($latitude, $longitude, +/-${accuracyMeters}m)';
}
