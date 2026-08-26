import '../../core/json_model.dart';

/// Response from Gemini stall image analysis.
///
/// Wire format: what Gemini API returns after analyzing a stall image.
/// Used to verify stall is detected and fully within frame.
/// Does NOT auto-fill any field.
class StallAnalysisResponse implements JsonModel {
  const StallAnalysisResponse({
    required this.stallStatus,
    required this.stallImageStatus,
    this.confidence = 1.0,
  });

  /// Stall detection: "detected" | "not_detected" | "unclear"
  /// If not "detected" → Error A8 (can't verify stall)
  final String stallStatus;

  /// Frame completeness: "complete" | "partially_captured" | "obstructed"
  /// If not "complete" → Error A15 (stall not fully in frame)
  final String stallImageStatus;

  /// Confidence score 0.0 - 1.0
  final double confidence;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'stallStatus': stallStatus,
    'stallImageStatus': stallImageStatus,
    'confidence': confidence,
  };

  StallAnalysisResponse copyWith({
    String? stallStatus,
    String? stallImageStatus,
    double? confidence,
  }) => StallAnalysisResponse(
    stallStatus: stallStatus ?? this.stallStatus,
    stallImageStatus: stallImageStatus ?? this.stallImageStatus,
    confidence: confidence ?? this.confidence,
  );
}
