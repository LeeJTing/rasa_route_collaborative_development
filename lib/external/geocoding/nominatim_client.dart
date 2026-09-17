import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin network boundary for Nominatim.
///
/// URI construction, response interpretation, caching and address composition
/// remain in the repository. This client owns only the external HTTP call and
/// Nominatim's process-wide request throttle.
class NominatimClient {
  NominatimClient();

  static const Duration _timeout = Duration(seconds: 8);
  static const int _minRequestGapMs = 1100;
  static DateTime? _lastRequestAt;

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'rasa-route/1.0 (com.rasaroute.app)',
    'Accept': 'application/json',
    'Accept-Language': 'en',
  };

  /// Returns decoded JSON, or null for every transport, status or decoding
  /// failure. This preserves the repository's best-effort contract.
  Future<dynamic> getJson(Uri uri) async {
    try {
      await _respectRateLimit();
      final http.Response response = await http
          .get(uri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// Nominatim permits at most one request per second for this app process.
  Future<void> _respectRateLimit() async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastRequestAt;
    if (last != null) {
      final int elapsedMs = now.difference(last).inMilliseconds;
      if (elapsedMs < _minRequestGapMs) {
        await Future<void>.delayed(
          Duration(milliseconds: _minRequestGapMs - elapsedMs),
        );
      }
    }
    _lastRequestAt = DateTime.now();
  }
}
