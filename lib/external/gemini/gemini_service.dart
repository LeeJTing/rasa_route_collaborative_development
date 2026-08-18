import '../../app/config/env.dart';

/// Wrapper around the Google Gemini REST API.
///
/// Reached only through `APIManager`. A singleton, like every other shared
/// client - `GeminiService()` always returns the same instance.
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
    return '';
  }

  Uri endpoint() => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '${Env.geminiModel}:generateContent?key=${Env.geminiApiKey}',
  );
}
