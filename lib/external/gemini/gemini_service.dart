import 'dart:convert';
import 'dart:io';

import '../../app/config/env.dart';
import '../../domain_model/local_food.dart';

/// Wrapper around the Google Gemini REST API.
///
/// Reached only through `APIManager`. A singleton, like every other shared
/// client - `GeminiService()` always returns the same instance.
///
/// Uses `dart:io.HttpClient` rather than a package - the scaffold's only
/// sanctioned new dependency is `provider` (see developer guideline).
///
/// Generic text/image methods live here. Feature prompts that need their own
/// API key/quota tracking live in a dedicated service (e.g.
/// `GeminiLandmarkService`); UC406's food-pairing prompt shares the shared key
/// and is validated by the calling repository, so it lives here too.
class GeminiService {
  factory GeminiService() => _instance;

  GeminiService._();

  static final GeminiService _instance = GeminiService._();

  /// Sends [imageBytes] with [prompt] and returns the model's raw text reply.
  ///
  /// [apiKey]/[model] override the shared [Env.geminiApiKey]/[Env.geminiModel]
  /// defaults - a feature-specific service (e.g. `GeminiLandmarkService`)
  /// passes its own key here so its usage/quota is tracked separately from
  /// whatever else calls this shared, generic service.
  Future<String> describeImage({
    required List<int> imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
    String? apiKey,
    String? model,
  }) async {
    return _generate(
      <Map<String, Object?>>[
        <String, Object?>{'text': prompt},
        <String, Object?>{
          'inline_data': <String, Object?>{
            'mime_type': mimeType,
            'data': base64Encode(imageBytes),
          },
        },
      ],
      apiKey: apiKey,
      model: model,
    );
  }

  /// Sends [prompt] as plain text and returns the model's raw text reply.
  ///
  /// Times out after [Env.apiTimeout] (UC406 requires the caller to handle a
  /// slow/failed AI response rather than hang the screen). Retries once on
  /// timeout or transient failure before giving up.
  ///
  /// [apiKey]/[model] - see [describeImage]'s doc.
  Future<String> generateText(
    String prompt, {
    int retries = 1,
    String? apiKey,
    String? model,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _generate(
          <Map<String, Object?>>[
            <String, Object?>{'text': prompt},
          ],
          apiKey: apiKey,
          model: model,
        ).timeout(Env.apiTimeout);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('Gemini request failed: $lastError');
  }

  /// Ordered models to try for one request: the requested [model] (or the
  /// shared default) first, then [Env.geminiFallbackModels]. The same shared
  /// fallback list is used whether the primary is [Env.geminiModel] (shared
  /// service) or [Env.geminiModelLandmark] (UC500's `GeminiLandmarkService`).
  /// If the primary model is temporarily unavailable (HTTP 429/5xx - high
  /// demand, common on loaded/free tiers), the next model in the list is
  /// tried automatically.
  List<String> _modelRotation(String? model) {
    final String primary = model ?? Env.geminiModel;
    final List<String> rotation = <String>[primary];
    for (final String candidate in Env.geminiFallbackModels) {
      if (!rotation.contains(candidate)) rotation.add(candidate);
    }
    return rotation;
  }

  Future<String> _generate(
    List<Map<String, Object?>> parts, {
    String? apiKey,
    String? model,
  }) async {
    Object? lastError;
    for (final String candidate in _modelRotation(model)) {
      try {
        return await _postToModel(
          parts,
          apiKey: apiKey ?? Env.geminiApiKey,
          model: candidate,
        );
      } on _GeminiTransientException catch (e) {
        // Model overloaded / rate-limited - move to the next one in the
        // rotation instead of failing the request.
        lastError = e;
      }
    }
    throw Exception('Gemini request failed: $lastError');
  }

  /// One HTTP POST to a single Gemini [model]. Throws [_GeminiTransientException]
  /// for 429/5xx so [._generate] can fail over to the next model.
  Future<String> _postToModel(
    List<Map<String, Object?>> parts, {
    required String apiKey,
    required String model,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .postUrl(endpoint(apiKey: apiKey, model: model))
          .timeout(Env.apiTimeout);
      request.headers.set('content-type', 'application/json');
      request.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'contents': <Map<String, Object?>>[
              <String, Object?>{'parts': parts},
            ],
          }),
        ),
      );
      final HttpClientResponse response = await request.close().timeout(
        Env.apiTimeout,
      );
      final String body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (_isTransientStatus(response.statusCode)) {
          throw _GeminiTransientException(
            'Gemini HTTP ${response.statusCode}: $body',
          );
        }
        throw Exception('Gemini HTTP ${response.statusCode}: $body');
      }

      final Map<String, dynamic> decoded =
          jsonDecode(body) as Map<String, dynamic>;
      final List<dynamic>? candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return '';

      final Map<String, dynamic> content =
          candidates.first['content'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final List<dynamic>? responseParts = content['parts'] as List<dynamic>?;
      if (responseParts == null || responseParts.isEmpty) return '';

      return (responseParts.first['text'] as String?) ?? '';
    } finally {
      client.close(force: true);
    }
  }

  /// 429 (rate limited) and 5xx (server overloaded - e.g. 503 "high demand")
  /// are transient: retrying the same model may keep failing, but a different
  /// model can succeed immediately. Other 4xx are permanent client errors and
  /// must surface right away.
  bool _isTransientStatus(int statusCode) =>
      statusCode == 429 || statusCode >= 500;

  /// [apiKey]/[model] override the shared [Env.geminiApiKey]/[Env.geminiModel]
  /// defaults - see [describeImage]'s doc for why.
  Uri endpoint({String? apiKey, String? model}) => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '${model ?? Env.geminiModel}:generateContent?key=${apiKey ?? Env.geminiApiKey}',
  );

  // ---------------------------------------------------------------------------
  // UC406 food pairing
  // ---------------------------------------------------------------------------

  /// Builds the food-pairing prompt from [selected] and [candidates], sends
  /// it through [generateText], and returns Gemini's raw reply for the calling
  /// repository to validate and rank.
  ///
  /// Only food data is sent (SELECTED FOOD + CANDIDATES). The caller has
  /// already excluded dietary-conflicting candidates, so no tourist profile,
  /// preferences or favourites are included.
  Future<String> generateFoodPairings({
    required LocalFood selected,
    required List<LocalFood> candidates,
  }) {
    final String prompt = <String>[
      _pairingInstructions,
      _buildDataSection(selected: selected, candidates: candidates),
    ].join('\n\n');
    return generateText(prompt);
  }

  /// The Gemini instructions for UC406 food pairing. Candidates carry a short
  /// attribute tail (category, cooking style, meal type, main taste) so the
  /// model can judge pairings, and the prompt forbids an empty result because
  /// the calling repository only sends a non-empty, dietary-safe candidate
  /// list - a pairing must always be returned when candidates exist.
  static const String _pairingInstructions = '''
You are a Malaysian local-food pairing assistant. Recommend the best foods from CANDIDATES to go with SELECTED FOOD.

RULES
1. Recommend only ids listed in CANDIDATES. Never recommend the SELECTED FOOD. Do not repeat a candidate. Up to 5.
2. Pair using your knowledge of these Malaysian dishes: spicy with something cooling or mildly sweet, savoury with a drink or dessert, rich with something light/refreshing, soft with crispy, a main with a suitable side, kuih or beverage. Use the category, cooking style, meal type and main taste shown after each id to judge the pairing.
3. matchPercentage: whole number 0-100 (90+ exceptional, 80s very good, 70s good, 60s reasonable, below 60 weak). Rank highest first; ranks start at 1.
4. reason: one short sentence saying how the food pairs with the SELECTED FOOD.
5. Candidates are already dietary-safe for the tourist, so set dietaryStatus "compatible" and warning null.
6. CANDIDATES is never empty, so you MUST always return at least one recommendation. If nothing pairs well, still recommend the best available candidate with a lower matchPercentage (50-60) and an honest reason. Never return an empty recommendations array.
7. Return ONLY JSON, no markdown, no extra text:
{
  "recommendations": [
    {"foodId": <int from CANDIDATES>, "rank": 1, "matchPercentage": 85, "reason": "...", "dietaryStatus": "compatible", "warning": null}
  ],
  "message": null
}
''';

  static String _buildDataSection({
    required LocalFood selected,
    required List<LocalFood> candidates,
  }) {
    final StringBuffer buffer = StringBuffer();

    buffer.writeln('SELECTED FOOD');
    buffer.writeln(_describeFood(selected));

    buffer.writeln();
    buffer.writeln('CANDIDATES');
    for (final LocalFood food in candidates) {
      buffer.writeln(_describeFood(food));
    }
    return buffer.toString();
  }

  static String _describeFood(LocalFood food) {
    final List<String> attributes = <String>[
      if (food.category.isNotEmpty) food.category,
      if (food.cookingStyle.isNotEmpty) food.cookingStyle,
      if (food.mealType.isNotEmpty) food.mealType,
      if (food.mainTaste.isNotEmpty) food.mainTaste,
    ];
    final String detail = attributes.isEmpty
        ? ''
        : ' (${attributes.join(', ')})';
    return '- id ${food.id}: ${food.name}$detail';
  }
}

/// A Gemini model that is temporarily unavailable (429/5xx) - the signal
/// `GeminiService._generate` catches to move to the next model in the
/// rotation instead of failing the request.
final class _GeminiTransientException implements Exception {
  _GeminiTransientException(this.message);

  final String message;

  @override
  String toString() => message;
}
