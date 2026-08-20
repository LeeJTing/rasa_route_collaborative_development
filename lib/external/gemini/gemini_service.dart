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
  Future<String> describeImage({
    required List<int> imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
  }) async {
    return _generate(<Map<String, Object?>>[
      <String, Object?>{'text': prompt},
      <String, Object?>{
        'inline_data': <String, Object?>{
          'mime_type': mimeType,
          'data': base64Encode(imageBytes),
        },
      },
    ]);
  }

  /// Sends [prompt] as plain text and returns the model's raw text reply.
  ///
  /// Times out after [Env.apiTimeout] (UC406 requires the caller to handle a
  /// slow/failed AI response rather than hang the screen). Retries once on
  /// timeout or transient failure before giving up.
  Future<String> generateText(String prompt, {int retries = 1}) async {
    Object? lastError;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _generate(<Map<String, Object?>>[
          <String, Object?>{'text': prompt},
        ]).timeout(Env.apiTimeout);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('Gemini request failed: $lastError');
  }

  Future<String> _generate(List<Map<String, Object?>> parts) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .postUrl(endpoint())
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

  Uri endpoint() => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '${Env.geminiModel}:generateContent?key=${Env.geminiApiKey}',
  );
}
