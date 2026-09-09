import 'dart:convert';
import 'dart:io';

import '../../app/config/env.dart';
import '../../domain_model/local_food.dart';


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

  /// Builds the food-pairing prompt from [selected], [candidates] and the
  /// signed-in tourist's [touristPreferences] (taste/cuisine names), sends it
  /// through [generateText], and returns Gemini's raw reply for the calling
  /// repository to validate and rank.
  ///
  /// The caller has already excluded dietary-conflicting candidates and
  /// preference-ranked them, so [touristPreferences] are only a matching
  /// signal for the model. Only food data plus preference names are sent - no
  /// other tourist profile data.
  Future<String> generateFoodPairings({
    required LocalFood selected,
    required List<LocalFood> candidates,
    List<String> touristPreferences = const <String>[],
  }) {
    final String prompt = <String>[
      _pairingInstructions,
      _buildDataSection(
        selected: selected,
        candidates: candidates,
        touristPreferences: touristPreferences,
      ),
    ].join('\n\n');
    return generateText(prompt);
  }

  static const String _pairingInstructions = '''
You are a Malaysian local-food pairing assistant. Recommend the foods from CANDIDATES that Malaysians would most naturally order, serve and eat together with SELECTED FOOD.

RECOGNISED MALAYSIAN ORDERING PATTERNS (strong hints - only return a food whose id is in CANDIDATES)
- A kopitiam drink (Kopi O, Kopi, Teh Tarik, Milo, Cham) is classically ordered with the kopitiam's OWN staples - Kaya Toast, half-boiled eggs, Roti Bakar / Roti Kahwin. Kuih or cake is only an occasional secondary extra, and only if it is kuih that same kopitiam would serve. Never fill the list with several kuih just because it is a drink.
- At a mamak, Roti Canai / Roti Telur / Mee Goreng Mamak is ordered with Teh Tarik or Kopi O.
- A hawker savoury main (fried kway teow, fried carrot cake, oyster omelette) is usually paired with a hawker drink (iced tea, lime juice, cincau) from the same stall, not with another heavy main.
- A dessert (ais kacang, bubur cha cha, cendol, pengat) is eaten on its own at a dessert/tea-time stall or with a light drink.

RULES
1. Recommend only ids listed in CANDIDATES. Never recommend the SELECTED FOOD. Do not repeat a candidate. Return exactly 5 recommendations whenever CANDIDATES has 5 or more items; if CANDIDATES has fewer than 5, recommend every remaining candidate. Never under-fill the list just because a pairing seems weak - include the best remaining candidate with a lower matchPercentage and an honest reason.
2. Compare all CANDIDATES with one another before ranking. Choose the combinations that best follow real Malaysian local dining habits, not combinations that are merely theoretically possible.
3. Use this ranking priority in order:
   a. Same venue: strongly prefer foods normally available at the same type of Malaysian venue as SELECTED FOOD, such as a kopitiam, mamak, hawker centre, food court, cafe, bakery or restaurant.
   b. Same meal occasion: strongly prefer foods commonly eaten together during the same breakfast, lunch, dinner, tea-time, supper, snack or dessert occasion.
   c. Local pairing style: prefer established Malaysian serving and ordering patterns, traditional accompaniments and combinations local diners would recognise as natural.
   d. Flavour compatibility: use sweetness, spice, richness, freshness and texture only as a secondary factor after venue, occasion and local eating style.
4. A candidate that shares the same venue and meal occasion with SELECTED FOOD MUST rank above a candidate that only provides flavour contrast. Do not recommend an item mainly because it is sweet, cooling, crispy or refreshing.
5. For a selected drink, prioritise foods commonly ordered with that drink at the same local venue and time of day - its natural partners are the venue's OWN staples first (e.g. kaya toast, half-boiled eggs, roti bakar at a kopitiam), then a light snack or kuih from that same venue. Never pair it with other full rice or noodle mains, and never fill all five slots with kuih or desserts. For a selected main dish, prioritise its usual local sides, drinks, condiments or desserts from the same dining setting.
6. Penalise pairings involving unrelated venue types, packaged standalone snacks, ceremonial or festive foods, and items normally eaten at a different meal occasion, unless the combination is genuinely common in Malaysian food culture.
7. Use the supplied category, cooking style, meal type and main taste together with reliable knowledge of Malaysian food culture. Infer only a general venue type when needed; do not invent a specific restaurant or claim that every venue serves the item.
8. TOURIST FOOD PREFERENCES (when present) lists tastes and cuisines/categories the tourist likes. It is a LOW-PRIORITY tie-break ONLY: judge same venue, same meal occasion and local pairing style FIRST, and never let preference matching push an unnatural pairing above a natural one. Do not fill all five slots with preference-matched foods just because they match the tourist's taste; at most one or two may be preference-only picks when nothing more natural is available. When the section is absent, rank only by pairing suitability.
9. matchPercentage must be a whole number from 0-100 (90+ exceptionally common and natural, 80s very good, 70s good, 60s reasonable, below 60 weak or unusual). Rank highest first; ranks start at 1.
10. reason must be one short sentence explaining the shared Malaysian venue, meal occasion or recognised local pairing style. Mention flavour only when it provides useful secondary support.
11. Candidates are already dietary-safe for the tourist, so set dietaryStatus "compatible" and warning null.
12. CANDIDATES is never empty. Return exactly 5 recommendations when at least 5 candidates exist; otherwise return every candidate. If fewer strong pairings exist, fill the remaining positions with the best available unused candidates using lower matchPercentage values and honest reasons. Never return an empty or under-filled recommendations array.
13. Return ONLY JSON, no markdown, no extra text:
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
    List<String> touristPreferences = const <String>[],
  }) {
    final StringBuffer buffer = StringBuffer();

    if (touristPreferences.isNotEmpty) {
      buffer.writeln('TOURIST FOOD PREFERENCES');
      buffer.writeln('- ${touristPreferences.join(', ')}');
      buffer.writeln();
    }

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
      if (food.foodType.isNotEmpty) food.foodType,
      if (food.category.isNotEmpty) food.category,
      if (food.cookingStyle.isNotEmpty) food.cookingStyle,
      if (food.mealType.isNotEmpty) food.mealType,
      if (food.mainTaste.isNotEmpty) food.mainTaste,
      ...food.tastes.where((String taste) => taste != food.mainTaste),
    ];
    final String detail = attributes.isEmpty
        ? ''
        : ' (${attributes.join(', ')})';
    return '- id ${food.id}: ${food.name}$detail';
  }
}

final class _GeminiTransientException implements Exception {
  _GeminiTransientException(this.message);

  final String message;

  @override
  String toString() => message;
}
