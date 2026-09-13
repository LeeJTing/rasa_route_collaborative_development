/// One place OpenStreetMap knows about, offered as an address suggestion on
/// the Add-New-Landmark form (and emitted for the composed address of a map
/// pin).
///
/// [address] is the DB-STYLE composed address - the same shape the
/// `restaurant.address` / `submitted_landmark.address` columns carry, e.g.
/// "PV18 Residences, Setapak, 53000 Kuala Lumpur" (see
/// `GeocodingRepository.composeAddress`). It is what lands in the form's
/// address field, never the raw `display_name` OSM returns.
///
/// [distanceMeters] is only filled in by the logic layer, which measures the
/// suggestion against the form's captured location and sorts the list
/// nearest-first - the repository itself has no reference point to measure
/// from.
class AddressSuggestion {
  const AddressSuggestion({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.distanceMeters = 0,
  });

  /// The composed, DB-style address text.
  final String address;

  final double latitude;
  final double longitude;

  /// How far this place is from the form's captured location, in metres.
  /// `0` until `LandmarkSubmissionLogic.searchAddresses` measures it.
  final double distanceMeters;

  /// The same suggestion with its distance measured - domain models are
  /// immutable carriers, so the logic layer builds a copy instead of mutating.
  AddressSuggestion withDistance(double metres) => AddressSuggestion(
    address: address,
    latitude: latitude,
    longitude: longitude,
    distanceMeters: metres,
  );
}
