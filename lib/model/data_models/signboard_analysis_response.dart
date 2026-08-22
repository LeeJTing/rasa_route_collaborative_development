import '../../core/json_model.dart';

/// Response from Gemini signboard image analysis.
///
/// Wire format: what Gemini API returns after analyzing a signboard image.
/// Used to extract restaurant name and verify frame completeness.
class SignboardAnalysisResponse implements JsonModel {
  const SignboardAnalysisResponse({
    required this.signboardStatus,
    this.textDetected,
    required this.signboardImageStatus,
    this.confidence = 1.0,
  });

  /// Signboard detection: "detected" | "not_detected" | "unclear"
  /// If "not_detected" or "unclear" → Error A7 (can't extract name)
  final String signboardStatus;

  /// Extracted text from signboard (restaurant name)
  /// Null if signboardStatus != "detected" or no text found
  /// Used for auto-filling Restaurant Name field
  final String? textDetected;

  /// Frame completeness: "complete" | "partially_captured" | "obstructed"
  /// If not "complete" → Error A19 (signboard not fully in frame)
  final String signboardImageStatus;

  /// Confidence score 0.0 - 1.0
  final double confidence;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'signboardStatus': signboardStatus,
    'textDetected': textDetected,
    'signboardImageStatus': signboardImageStatus,
    'confidence': confidence,
  };

  SignboardAnalysisResponse copyWith({
    String? signboardStatus,
    String? textDetected,
    String? signboardImageStatus,
    double? confidence,
  }) => SignboardAnalysisResponse(
    signboardStatus: signboardStatus ?? this.signboardStatus,
    textDetected: textDetected ?? this.textDetected,
    signboardImageStatus: signboardImageStatus ?? this.signboardImageStatus,
    confidence: confidence ?? this.confidence,
  );
}
