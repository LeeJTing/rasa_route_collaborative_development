import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app/config/env.dart';
import '../../domain_model/address_suggestion.dart';
import '../../domain_model/tourist_location.dart';

/// OpenStreetMap geocoding through the public Nominatim service - the two
/// directions the Add-New-Landmark form needs:
///
///   * [searchAddresses] - the address field's live suggestions: what the
///     tourist types ("PV") is resolved to real OSM places (buildings, roads,
///     areas), each carrying coordinates so the map pin can follow the
///     selection;
///   * [reverseGeocodeAddress] - the composed address behind a map pin, so
///     moving the pin can fill the address field (and the "Use the map pin's
///     address" button has something to fill with).
///
/// COMPOSED, NOT RAW: every returned address is built by [composeAddress] in
/// the same shape the `restaurant.address` / `submitted_landmark.address`
/// columns already carry on this project - e.g.
/// "G-42, Platinum PV128, Jalan Genting Kelang, Taman Danau Kota, 53300
/// Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur" - because a landmark's
/// address is displayed exactly like a restaurant's ("Landmark Information"
/// card), so the two must read the same.
///
/// Nominatim usage policy (https://operations.osmfoundation.org/policies/nominatim):
/// requests are throttled to one per second GLOBALLY (the throttle is static,
/// because the app instance is the requester, not one repository), carry an
/// identifying User-Agent, and every result is cached for the life of the
/// form session, so re-typing the same query costs nothing.
///
/// Best-effort, like `LinkCheckRepository`: nothing here throws. A failed or
/// rejected lookup returns `null` (VM shows "search unavailable"), while a
/// lookup that worked but matched nothing returns an empty list (VM shows
/// "no matching addresses").
class GeocodingRepository {
  GeocodingRepository();

  static const Duration _timeout = Duration(seconds: 8);

  /// Nominatim's policy allows at most one request per second; 1100 ms leaves
  /// a margin.
  static const int _minRequestGapMs = 1100;
  static DateTime? _lastRequestAt;

  /// How many results a search asks for. The logic layer re-sorts them by
  /// distance anyway; the request already walks outwards from the anchor, so
  /// a small window is enough.
  static const int searchLimit = 8;

  /// The `viewbox` half-width around the captured location (roughly 35 km
  /// north/south and east/west) that biases the search towards the area the
  /// tourist is standing in. `bounded=0`, so an exact match far away is still
  /// returned - the form flags the distance rather than hiding it.
  static const double _biasDegrees = 0.35;

  /// The address cap shared with `LandmarkSubmissionLogic.maxAddressLength`
  /// and the `varchar(150)` column behind `submitted_landmark.address` - a
  /// composed address is trimmed (whole trailing parts dropped first) to fit.
  static const int maxComposedAddressLength = 150;

  /// Nominatim requires an identifying User-Agent.
  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'rasa-route/1.0 (com.rasaroute.app)',
    'Accept': 'application/json',
    'Accept-Language': 'en',
  };

  static const int _cacheLimit = 25;

  /// Address searches already performed on this device session, keyed by
  /// anchor + query. Insertion-ordered, capped at [_cacheLimit].
  final Map<String, List<AddressSuggestion>> _searchCache =
      <String, List<AddressSuggestion>>{};

  /// Reverse lookups already performed, keyed by the rounded spot. Failures
  /// are never cached.
  final Map<String, String> _reverseCache = <String, String>{};

  /// Live address search for the form's address field, biased around
  /// [around] (the captured location). Returns `null` when the lookup failed
  /// (offline, rate-limited, bad response) and an empty list when the service
  /// answered with nothing usable.
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <AddressSuggestion>[];

    final String key = '${_spotKey(around)}|${trimmed.toLowerCase()}';
    final List<AddressSuggestion>? cached = _searchCache[key];
    if (cached != null) return cached;

    final Uri? uri = _searchUri(trimmed, around);
    if (uri == null) return null;
    final dynamic decoded = await _getJson(uri);
    if (decoded is! List) return null;

    final List<AddressSuggestion> results = <AddressSuggestion>[];
    final Set<String> seen = <String>{};
    for (final dynamic item in decoded) {
      if (item is! Map) continue;
      final Map<String, dynamic> json = Map<String, dynamic>.from(item);
      final String address = composeAddress(json);
      if (address.isEmpty) continue;
      final double? latitude = _asDouble(json['lat']);
      final double? longitude = _asDouble(json['lon']);
      if (latitude == null || longitude == null) continue;
      if (!seen.add(address.toLowerCase())) continue;
      results.add(
        AddressSuggestion(
          address: address,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }

    final List<AddressSuggestion> value = results.isEmpty
        ? const <AddressSuggestion>[]
        : results;
    _remember(_searchCache, key, value);
    return value;
  }

  /// The composed address of the point ([location]) - `null` when the lookup
  /// failed or OpenStreetMap has no usable address there (the form then keeps
  /// whatever is in the field and says so).
  Future<String?> reverseGeocodeAddress(TouristLocation location) async {
    if (!location.isKnown) return null;

    final String key = _spotKey(location);
    final String? cached = _reverseCache[key];
    if (cached != null) return cached;

    final Uri? uri = _reverseUri(location);
    if (uri == null) return null;
    final dynamic decoded = await _getJson(uri);
    if (decoded is! Map) return null;

    final String address = composeAddress(Map<String, dynamic>.from(decoded));
    if (address.isEmpty) return null;
    _remember(_reverseCache, key, address);
    return address;
  }

  /// Builds the DB-STYLE address for one Nominatim item (search result or
  /// reverse response), mirroring the shape of the project's existing
  /// `restaurant.address` rows:
  ///
  ///   [name], [house number, road], [area], [postcode city], [state]
  ///
  /// e.g. "PV18 Residences, Setapak, 53000 Kuala Lumpur" or "16, Jalan Sri
  /// Damak 18, Taman Sri Andalas, 41200 Klang, Selangor".
  ///
  /// Rules (all silent, because OSM data is patchy):
  ///   * missing parts are skipped; repeated adjacent parts are collapsed
  ///     (a road result often carries the same name twice);
  ///   * "Unnamed Road" is dropped - it is OSM's placeholder, not an address;
  ///   * the country ("Malaysia") is never appended - the DB rows do not
  ///     carry it;
  ///   * the Kuala Lumpur / Labuan / Putrajaya federal territories get their
  ///     full "Wilayah Persekutuan ..." name back (OSM omits `state` for
  ///     them, but reports `ISO3166-2-lvl4`, which matches the DB rows);
  ///   * the result is trimmed to [maxComposedAddressLength] by dropping
  ///     whole trailing parts (state first, then the city part, ...);
  ///   * when no structured parts exist at all, a trimmed `display_name`
  ///     (sans ", Malaysia") is used as-is.
  ///
  /// Pure and public so it can be unit-tested without any network.
  static String composeAddress(Map<String, dynamic> json) {
    final Map<String, dynamic> address = json['address'] is Map
        ? Map<String, dynamic>.from(json['address'] as Map)
        : const <String, dynamic>{};
    String text(Object? value) => value is String ? value.trim() : '';
    String part(String key) => text(address[key]);

    final List<String> parts = <String>[];
    void add(String value) {
      final String trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (trimmed.toLowerCase() == 'unnamed road') return;
      if (parts.isNotEmpty &&
          parts.last.toLowerCase() == trimmed.toLowerCase()) {
        return;
      }
      parts.add(trimmed);
    }

    add(text(json['name']));
    final String houseNumber = part('house_number');
    final String road = part('road');
    if (houseNumber.isNotEmpty && road.isNotEmpty) {
      add('$houseNumber, $road');
    } else {
      add(houseNumber.isEmpty ? road : houseNumber);
    }

    // ONE area component, most specific first - matching the single Taman /
    // locality the DB addresses carry.
    for (final String key in const <String>[
      'suburb',
      'neighbourhood',
      'quarter',
      'village',
      'hamlet',
    ]) {
      final String value = part(key);
      if (value.isNotEmpty) {
        add(value);
        break;
      }
    }

    String city = part('city');
    if (city.isEmpty) city = part('town');
    if (city.isEmpty) city = part('municipality');
    if (city.isEmpty) city = part('village');
    final String postcode = part('postcode');
    add(<String>[postcode, city].where((String s) => s.isNotEmpty).join(' '));

    String state = part('state');
    if (state.isEmpty) {
      state = _federalTerritory(part('ISO3166-2-lvl4'));
    }
    add(state);

    String result = parts.join(', ');
    if (result.isEmpty) {
      result = text(
        json['display_name'],
      ).replaceAll(RegExp(r',\s*Malaysia\s*$'), '').trim();
    }
    return _trimToLimit(result, parts);
  }

  /// The full name of the three Malaysian federal territories, whose OSM
  /// entries carry no `state` key - only an ISO 3166-2 code.
  static String _federalTerritory(String isoCode) {
    switch (isoCode.toUpperCase()) {
      case 'MY-14':
        return 'Wilayah Persekutuan Kuala Lumpur';
      case 'MY-15':
        return 'Wilayah Persekutuan Labuan';
      case 'MY-16':
        return 'Wilayah Persekutuan Putrajaya';
      default:
        return '';
    }
  }

  /// Trims [result] to [maxComposedAddressLength] by dropping whole trailing
  /// [parts] (state, then the postcode/city block, ...) so the text never ends
  /// mid-word; only a single over-long part is hard-truncated. A trailing
  /// separator left by the cut is removed.
  static String _trimToLimit(String result, List<String> parts) {
    String value = result;
    if (value.length > maxComposedAddressLength && parts.length > 1) {
      final List<String> remaining = List<String>.of(parts);
      while (remaining.length > 1 &&
          remaining.join(', ').length > maxComposedAddressLength) {
        remaining.removeLast();
      }
      value = remaining.join(', ');
    }
    if (value.length > maxComposedAddressLength) {
      value = value.substring(0, maxComposedAddressLength);
    }
    return value.replaceAll(RegExp(r'[,\s]+$'), '').trim();
  }

  Uri? _searchUri(String query, TouristLocation around) {
    final Uri? base = _baseUri();
    if (base == null) return null;
    final Map<String, String> params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '$searchLimit',
      'countrycodes': 'my',
      'accept-language': 'en',
    };
    if (around.isKnown) {
      // viewbox is left,top,right,bottom.
      params['viewbox'] =
          '${around.longitude - _biasDegrees},'
          '${around.latitude + _biasDegrees},'
          '${around.longitude + _biasDegrees},'
          '${around.latitude - _biasDegrees}';
      params['bounded'] = '0';
    }
    return base.replace(path: '${base.path}/search', queryParameters: params);
  }

  Uri? _reverseUri(TouristLocation location) {
    final Uri? base = _baseUri();
    if (base == null) return null;
    return base.replace(
      path: '${base.path}/reverse',
      queryParameters: <String, String>{
        'lat': '${location.latitude}',
        'lon': '${location.longitude}',
        'format': 'jsonv2',
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'en',
      },
    );
  }

  Uri? _baseUri() {
    final Uri? uri = Uri.tryParse(Env.osmNominatimUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  /// GETs [uri] (rate-limited) and decodes the JSON body - `null` on any
  /// failure, including non-2xx responses and malformed bodies.
  Future<dynamic> _getJson(Uri uri) async {
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

  /// Waits out the remainder of the one-request-per-second window, then
  /// stamps the request time. Static, so it covers every instance.
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

  static String _spotKey(TouristLocation location) =>
      '${location.latitude.toStringAsFixed(5)},'
      '${location.longitude.toStringAsFixed(5)}';

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Inserts into a small insertion-ordered cache, evicting the oldest entry
  /// once the cache exceeds [_cacheLimit].
  void _remember<T>(Map<String, T> cache, String key, T value) {
    cache[key] = value;
    while (cache.length > _cacheLimit) {
      cache.remove(cache.keys.first);
    }
  }
}
