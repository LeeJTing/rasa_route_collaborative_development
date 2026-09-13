import '../../core/json_model.dart';

/// Response from Gemini's "are these two photos the same restaurant?"
/// question - the near-duplicate check behind the Add-Landmark Confirm click.
///
/// The two images are the photo the tourist just captured and one stored for
/// a NEARBY place whose name looks like theirs (see
/// `LandmarkSubmissionLogic.similarNearbyPlaces`). A "yes" is what raises the
/// "did you mean this restaurant?" question - the tourist decides, never the
/// model on its own.
class PlacePhotoMatchResponse implements JsonModel {
  const PlacePhotoMatchResponse({
    required this.samePlace,
    this.confidence = 0,
    this.reason = '',
  });

  /// Whether the model judges both photos to show the SAME restaurant/stall.
  /// Spelling differences of one name ("Ali & Abu" vs "Ali and Abu") count as
  /// the same place HERE - the photos are the evidence, and the tourist still
  /// confirms before anything is merged.
  final bool samePlace;

  /// The model's confidence in [samePlace], 0.0 - 1.0.
  final double confidence;

  /// One short sentence of justification - for logs, never shown to the
  /// tourist.
  final String reason;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'samePlace': samePlace,
    'confidence': confidence,
    'reason': reason,
  };
}
