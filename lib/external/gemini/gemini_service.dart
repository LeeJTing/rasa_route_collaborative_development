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
  /// shared default) first, then [Env.geminiFallbackModels]. If the primary
  /// model is temporarily unavailable (HTTP 429/5xx - high demand, common on
  /// loaded/free tiers), the next model in the list is tried automatically.
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

  /// The Gemini system instructions for UC406 food pairing - a condensed,
  /// single-source version of the UC406 prompt spec. Only food data is sent
  /// (SELECTED FOOD + CANDIDATES); dietary conflicts are already removed
  /// client-side, so the model picks the best pairings and flags only
  /// incomplete-allergen warnings.
  static const String _pairingInstructions = '''
You are a Malaysian local-food pairing assistant. From CANDIDATES, recommend the foods that pair best with SELECTED FOOD.

STRICT RULES
1. Use ONLY the supplied data. Never invent or guess a food, food ID, ingredient, allergen, dietary label, flavour, texture, cooking style, cultural fact, or meal suitability. Never modify a food ID.
2. Recommend only foods listed in CANDIDATES. Never recommend SELECTED FOOD. Do not repeat a candidate. Return fewer when there are not enough eligible candidates, and never more than maximumResults or 5.
3. Every candidate has already been screened against the tourist's dietary restrictions, so do not exclude or re-evaluate conflicts. However, if a candidate's allergen, ingredient or preparation information is incomplete or uncertain, set dietaryStatus to "warning" and state exactly what to verify with the seller. Never claim an uncertain food is safe.
4. Pairing: prefer foods that complement SELECTED FOOD (e.g. rich with light/refreshing, spicy with cooling/mildly sweet, savoury with a beverage or dessert, soft with crispy, a main with a side/kuih/drink). Do not credit an attribute that is missing from the input. Similarity alone is not a high score.
5. matchPercentage: a whole integer 0-100 expressing recommendation strength, not probability or a safety score. Calibrate: 90-100 exceptional (strong evidence, clear complementarity, no concern); 80-89 very good; 70-79 good; 60-69 reasonable; below 60 weak (use only when very few options). Candidates with uncertain dietary information get at most 79.
6. Rank by matchPercentage from highest to lowest. The first rank is 1 and ranks are consecutive. On a tie, keep CANDIDATES order.

REASON: one sentence under 35 words. State how the candidate pairs with SELECTED FOOD, naming a concrete factor (taste, texture, cooking style, meal type, or balancing effect). Describe complementarity, not similarity. No generic claims such as "great match". Do not repeat the warning.

WARNING (only when dietaryStatus is "warning"): under 25 words. Name the missing, uncertain, or cross-contamination information and what to confirm with the seller. Do not claim the food is safe.

OUTPUT: one valid JSON object only - standard JSON, straight double quotes, no markdown, no code fences, no commentary, no trailing commas, no extra fields.
{
  "recommendations": [
    {
      "foodId": <int from CANDIDATES>,
      "rank": 1,
      "matchPercentage": 85,
      "reason": "Concise explanation supported by the supplied data.",
      "dietaryStatus": "compatible",
      "warning": null
    }
  ],
  "message": null
}
When no candidate is suitable, return exactly:
{"recommendations": [], "message": "No suitable food pairings were found for your dietary requirements."}
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
    return '- id ${food.id}: ${food.name} | category: ${_value(food.category)}';
  }

  static String _value(String value) =>
      value.trim().isEmpty ? 'not provided' : value.trim();
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
