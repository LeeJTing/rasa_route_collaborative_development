import '../../core/json_model.dart';

/// Response from Gemini's SECOND signboard question: which Chinese
/// character style is ACTUALLY PAINTED on the signboard?
///
/// Asked because the first reading can be self-consistently wrong: when the
/// model transcribes a Traditional signboard in Simplified characters AND
/// labels it "simplified", nothing in the app can tell that the sign itself
/// was Traditional (a transcription only proves a contradiction, never an
/// omission - see `isScriptVariantContradiction`). A separately-framed
/// question, answered with the characters the model says it read off the
/// sign, is the second opinion that catches it (user report 2026-09-14:
/// "why the gemini return simplified chinese for the signboard recognition
/// while the signboard is having traditional chinese again").
///
/// The answer is used to RESTORE the transcription to the painted style
/// (`correctChineseScriptStyle`), never to replace what was read.
class SignboardScriptCheckResponse implements JsonModel {
  const SignboardScriptCheckResponse({
    this.paintedStyle = 'unknown',
    this.exampleCharacters = '',
    this.reason = '',
  });

  /// The style painted on the sign, as one of:
  ///   * 'traditional' - the painted glyphs carry the complex forms
  ///     (樓 / 記 / 麵 / 雞): judged by stroke count, never by habit;
  ///   * 'simplified' - the painted glyphs carry the reduced forms
  ///     (楼 / 记 / 面 / 鸡);
  ///   * 'none' - the signboard carries no Chinese characters at all;
  ///   * 'unknown' - the question could not be answered.
  ///
  /// Anything else is normalised to 'unknown' by `fromJson`, so a caller
  /// only ever compares against these four values.
  final String paintedStyle;

  /// The characters the model actually READ OFF THE SIGN (e.g. "天義樓").
  /// Carried so the answer can be judged rather than trusted blindly, and so
  /// a later log can show what the sign was said to paint.
  final String exampleCharacters;

  /// One short sentence of justification - for logs, never shown to the
  /// tourist.
  final String reason;

  /// Whether [paintedStyle] is one of the two styles whose characters can be
  /// restored (`correctChineseScriptStyle`).
  bool get namesAStyle =>
      paintedStyle == 'traditional' || paintedStyle == 'simplified';

  factory SignboardScriptCheckResponse.fromJson(Map<String, dynamic> json) {
    return SignboardScriptCheckResponse(
      paintedStyle: normaliseStyle(
        JsonReader.asStringOrNull(json['paintedStyle']),
      ),
      exampleCharacters: JsonReader.asString(json['exampleCharacters']),
      reason: JsonReader.asString(json['reason']),
    );
  }

  /// The wire label -> one of the four known answers. A missing or
  /// unrecognised label means "the question was not answered", which callers
  /// treat exactly like an unavailable check.
  static String normaliseStyle(String? raw) {
    return switch ((raw ?? '').trim().toLowerCase()) {
      'traditional' => 'traditional',
      'simplified' => 'simplified',
      'none' => 'none',
      _ => 'unknown',
    };
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'paintedStyle': paintedStyle,
    'exampleCharacters': exampleCharacters,
    'reason': reason,
  };
}
