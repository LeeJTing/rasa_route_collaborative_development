import 'package:http/http.dart' as http;

/// Result returned by the external HTTP boundary without exposing
/// `package:http` to repositories.
class LinkValidationResponse {
  const LinkValidationResponse({
    required this.statusCode,
    required this.bodyBytes,
  });

  final int statusCode;
  final List<int> bodyBytes;
}

/// Executes public-link GET requests for website and image validation.
class LinkValidationClient {
  LinkValidationClient();

  static const Duration _timeout = Duration(seconds: 5);

  /// Returns null for timeout, DNS, redirect-loop and other transport errors.
  Future<LinkValidationResponse?> get(Uri uri) async {
    try {
      final http.Response response = await http.get(uri).timeout(_timeout);
      return LinkValidationResponse(
        statusCode: response.statusCode,
        bodyBytes: response.bodyBytes,
      );
    } catch (_) {
      return null;
    }
  }
}
