import 'opening_hour.dart';

/// What a place ALREADY on record stores for one submission's name - the
/// details the Add-Landmark form fills itself with once the tourist confirms
/// the restaurant name (user request 2026-09-14): a re-submission then reviews
/// and corrects the phone, website, address and week that are already on
/// file instead of retyping them from scratch.
///
/// Plain data - `LandmarkSubmissionLogic` builds it from the matched
/// `restaurant` row (or an earlier `submitted_landmark`) and the form copies
/// what it needs. Empty values mean "nothing stored": the form leaves its own
/// field alone rather than blanking it.
class StoredPlaceDetails {
  const StoredPlaceDetails({
    required this.name,
    this.isRestaurant = true,
    this.phone = '',
    this.website = '',
    this.address = '',
    this.openingHours = const <OpeningHour>[],
  });

  /// The place's name AS STORED - the record's own spelling of the name the
  /// form looked up (the lookup itself matches ignoring case and punctuation,
  /// so adopting it is a spelling alignment, never a rename).
  final String name;

  /// True for a catalogue `restaurant`, false for an earlier submitted
  /// landmark.
  final bool isRestaurant;

  final String phone;
  final String website;
  final String address;

  /// The stored week, one row per day - the same shape the detail screens
  /// read (tails merged, each row carrying its own [Weekday]).
  final List<OpeningHour> openingHours;

  /// Whether the record holds anything beyond its name - false means the
  /// form has nothing to prefill from it.
  bool get hasDetails =>
      phone.isNotEmpty ||
      website.isNotEmpty ||
      address.isNotEmpty ||
      openingHours.isNotEmpty;
}
