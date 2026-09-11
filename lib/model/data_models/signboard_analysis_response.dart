import '../../core/json_model.dart';

/// Response from Gemini signboard image analysis.
///
/// Wire format: what Gemini API returns after analyzing a signboard image.
/// Used to extract restaurant name and verify frame completeness.
class SignboardAnalysisResponse implements JsonModel {
  const SignboardAnalysisResponse({
    required this.signboardStatus,
    this.textDetected,
    this.nameOriginalScript,
    this.scriptVariant = 'n/a',
    this.languageScript = 'latin',
    required this.signboardImageStatus,
    this.confidence = 1.0,
  });

  /// Signboard detection: "detected" | "not_detected" | "unclear"
  /// If "not_detected" or "unclear" → Error A7 (can't extract name)
  final String signboardStatus;

  /// The restaurant name, romanised to Latin script when the signboard is
  /// non-Latin (see [nameOriginalScript] for the exact text as displayed).
  /// Null if signboardStatus != "detected" or no text found. Used for
  /// auto-filling the Restaurant Name field.
  final String? textDetected;

  /// For non-Latin signboards (Chinese / Tamil / Jawi) the name exactly as
  /// it appears on the signboard, e.g. 海天楼 or அரவிந்த். Null (or equal to
  /// [textDetected]) when the signboard is Latin-script.
  final String? nameOriginalScript;

  /// Script of the detected name: "latin" | "chinese" | "tamil" | "jawi" |
  /// "mixed". Defaults to "latin" when the field is absent.
  final String languageScript;

  /// The Chinese style ACTUALLY PAINTED on the signboard, read off the image
  /// itself: "simplified" | "traditional" | "mixed" | "n/a" (name is not
  /// Chinese). Used to check that [nameOriginalScript] was copied exactly
  /// instead of being "turned" into the other style - see
  /// `LandmarkSubmissionLogic.displaySignboardName`.
  final String scriptVariant;

  /// Frame completeness: "complete" | "partially_captured" | "obstructed"
  /// If not "complete" → Error A19 (signboard not fully in frame)
  final String signboardImageStatus;

  /// Confidence score 0.0 - 1.0
  final double confidence;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'signboardStatus': signboardStatus,
    'textDetected': textDetected,
    'nameOriginalScript': nameOriginalScript,
    'scriptVariant': scriptVariant,
    'languageScript': languageScript,
    'signboardImageStatus': signboardImageStatus,
    'confidence': confidence,
  };

  SignboardAnalysisResponse copyWith({
    String? signboardStatus,
    String? textDetected,
    String? nameOriginalScript,
    String? scriptVariant,
    String? languageScript,
    String? signboardImageStatus,
    double? confidence,
  }) => SignboardAnalysisResponse(
    signboardStatus: signboardStatus ?? this.signboardStatus,
    textDetected: textDetected ?? this.textDetected,
    nameOriginalScript: nameOriginalScript ?? this.nameOriginalScript,
    scriptVariant: scriptVariant ?? this.scriptVariant,
    languageScript: languageScript ?? this.languageScript,
    signboardImageStatus: signboardImageStatus ?? this.signboardImageStatus,
    confidence: confidence ?? this.confidence,
  );
}
