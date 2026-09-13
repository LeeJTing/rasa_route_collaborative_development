/// One place near the restaurant a tourist is adding whose NAME looks like
/// theirs - a catalogue `restaurant` row or an earlier submitted landmark
/// (see `LandmarkSubmissionLogic.similarNearbyPlaces`).
///
/// The Add-Landmark Confirm click uses these to ask Gemini whether its stored
/// photo and the tourist's own capture show the same restaurant; a "yes"
/// raises the "did you mean this restaurant?" question, which the TOURIST
/// answers. Nothing is merged on the model's word alone.
class SimilarPlaceCandidate {
  const SimilarPlaceCandidate({
    required this.id,
    required this.name,
    required this.isRestaurant,
    required this.distanceMetres,
    this.imageUrl,
    this.address = '',
  });

  /// `restaurant_id` when [isRestaurant], else `landmark_id`.
  final int id;

  /// The place's own name as stored - what the question shows the tourist.
  final String name;

  /// True for a catalogue restaurant row, false for a submitted landmark.
  /// The two are merged differently at submit time (a restaurant keeps its
  /// curated data; a landmark can take the tourist's contact/hours).
  final bool isRestaurant;

  /// How far the place is from the form's location, in metres (haversine).
  final double distanceMetres;

  /// The place's stored photo - a signboard/stall photo for a submitted
  /// landmark, the shop photo for a restaurant. Candidates WITHOUT one are
  /// never returned: there would be nothing to compare.
  final String? imageUrl;

  /// The place's stored address, when it has one ('' otherwise).
  final String address;
}
