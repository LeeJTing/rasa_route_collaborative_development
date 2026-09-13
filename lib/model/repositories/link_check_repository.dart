import 'package:http/http.dart' as http;

/// Checks whether a tourist-supplied website URL is reachable - used by the
/// Add Landmark form's optional website field.
///
/// A site counts as reachable when a GET answers within 5s with an HTTP
/// status in 200-399; anything else (404/500/timeout/DNS failure/redirect
/// loop) is NOT reachable. `package:http` follows redirects for GET by
/// default.
///
/// The only repository that touches `package:http` directly (kept behind the
/// repository facade so logic/ViewModel never import a client). Best-effort
/// and deliberately strict about status codes - callers treat `false` as
/// "not reachable".
///
/// NOTE (SSRF): this runs from the client for form validation only. For
/// production, the equivalent check belongs on a backend so private/internal
/// IPs can be blocked and verification logic stays server-side.
class LinkCheckRepository {
  LinkCheckRepository();

  static const Duration _timeout = Duration(seconds: 5);

  Future<bool> isWebsiteReachable(String url) async {
    try {
      final Uri uri = Uri.parse(url.trim());
      if (!uri.hasScheme ||
          !uri.hasAuthority ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        return false;
      }
      final http.Response response = await http.get(uri).timeout(_timeout);
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  /// Downloads a PUBLIC photo - a nearby place's stored signboard/stall photo,
  /// so it can be sent to Gemini next to the tourist's own capture (the
  /// near-duplicate check, see `LandmarkSubmissionLogic`). Null on any failure
  /// (bad URL, timeout, no connection, non-2xx): a candidate whose photo
  /// cannot be read is simply skipped, never an error the tourist sees.
  Future<List<int>?> fetchImageBytes(String url) async {
    try {
      final Uri uri = Uri.parse(url.trim());
      if (!uri.hasScheme ||
          !uri.hasAuthority ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final http.Response response = await http.get(uri).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
