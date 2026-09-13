import '../../core/json_model.dart';

/// Response from Gemini's SECOND signboard question: does the name the
/// tourist TYPED still match the name painted on the signboard they captured?
///
/// Only asked when the form's name differs from Gemini's own reading - an
/// untouched reading needs no second opinion (see
/// `LandmarkSubmissionLogic.nameMatchesSignboard`).
class SignboardNameMatchResponse implements JsonModel {
  const SignboardNameMatchResponse({
    required this.matchScore,
    this.matched = false,
    this.reason = '',
  });

  /// How well the typed name matches the signboard's own name, 0.0 - 1.0
  /// (the wire format's 0-100 score, divided by 100).
  ///
  /// 1.0 is "the same name", INCLUDING the allowances a person would make:
  /// a translation or romanisation, the same name in another script, a
  /// dropped generic word ("Restoran", "Restaurant", "Kedai"), a shortened
  /// but still distinctive form, spacing, capitalisation and small typos.
  /// 0.0 is a different name entirely.
  final double matchScore;

  /// The model's own yes/no answer to the same question. The app gates on the
  /// SCORE (see `LandmarkSubmissionLogic.signboardNameMatchThreshold`); this
  /// rides along for logging and for the stub fallback.
  final bool matched;

  /// One short sentence of justification - for logs, never shown to the
  /// tourist (the form's message stays plain, see
  /// `AddLandmarkViewModel.signboardNameMismatchMessage`).
  final String reason;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'matchScore': matchScore,
    'matched': matched,
    'reason': reason,
  };
}
