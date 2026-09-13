import 'region.dart';

/// The country rings that answer "is this coordinate inside Malaysia?" - the
/// ONE dataset the map and the Add-Landmark land check both measure against.
///
/// `MapRepository` PUBLISHES the rings it fetched for the map
/// (`map_country_rings`: the real coastline, simplified to ~300 m and buffered
/// ~2 km outward, plus the islands no boundary dataset has) here the first
/// time the map loads - once per process, because the boundaries never change.
///
/// `LocationRules` asks here BEFORE its own built-in polygons, so the form can
/// never tell a tourist they are "not in Malaysia" while the map is drawing
/// their dot inside the country (user report 2026-09-14: a mocked fix on
/// Pulau Redang and in Perlis was turned away - the form still had a
/// hand-drawn polygon of its own with no island and a west edge that clipped
/// Perlis).
///
/// Null until something has been published (a cold start with no connection,
/// and every unit test): the built-in polygons in `LocationRules` answer then,
/// so the check stays local, synchronous and offline-safe.
abstract final class MalaysiaBoundary {
  static List<CountryOutline>? _published;

  /// The published rings, or null until `MapRepository` has fetched them.
  static List<CountryOutline>? get publishedRings => _published;

  /// Publishes the rings the map masks with. Ignored when empty - a failed
  /// fetch must never replace the answer with nothing.
  static void publishRings(List<CountryOutline> rings) {
    if (rings.isEmpty) return;
    _published = List<CountryOutline>.unmodifiable(rings);
  }

  /// Forgets the published rings. Tests only - the app publishes once and
  /// keeps them for the life of the process.
  static void forgetRings() {
    _published = null;
  }
}
