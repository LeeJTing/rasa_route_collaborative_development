import 'dart:convert';
import 'dart:io';

import '../../app/config/env.dart';

/// Wrapper around the Google Gemini REST API.
///
/// Reached only through `APIManager`. A singleton, like every other shared
/// client - `GeminiService()` always returns the same instance.
///
/// Uses `dart:io.HttpClient` rather than a package - the scaffold's only
/// sanctioned new dependency is `provider` (see developer guideline).
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
