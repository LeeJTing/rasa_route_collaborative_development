/// What the model returned for one photo, after the logic layer matched the
/// predictions against `local_food`.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class RecognitionResult {
  const RecognitionResult({
    required this.imagePath,
    required this.predictions,
    this.recognisedAt,
    required this.rawResponse,
  });

  final String imagePath;
  final List<RecognitionPrediction> predictions;
  final DateTime? recognisedAt;
  final String rawResponse;
}

/// One candidate dish returned by the model. [confidence] is 0..1;
/// [matchedLocalFoodId] is set once the label resolves to a catalogue row.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class RecognitionPrediction {
  const RecognitionPrediction({
    required this.label,
    required this.confidence,
    this.matchedLocalFoodId,
  });

  final String label;
  final double confidence;
  final int? matchedLocalFoodId;
}
