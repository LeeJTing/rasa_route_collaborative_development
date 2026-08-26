import '../../core/json_model.dart';
import '../../domain_model/map_place.dart';

/// Wire shape of `public.place` - the searchable geography behind REQ102_19.
///
/// Read-only to the app: the table is seeded and maintained by migration, and
/// its RLS policy grants `select` only.
class PlaceDataModel implements JsonModel {
  const PlaceDataModel({
    required this.placeId,
    required this.name,
    required this.kind,
    required this.stateName,
    required this.latitude,
    required this.longitude,
    this.zoom,
    this.aliases,
  });

  final int placeId;
  final String name;

  /// `city` | `town` | `area` | `landmark`.
  final String kind;

  final String stateName;
  final double latitude;
  final double longitude;
  final double? zoom;

  /// Comma-separated alternates as stored.
  final String? aliases;

  factory PlaceDataModel.fromJson(Map<String, dynamic> json) => PlaceDataModel(
    placeId: JsonReader.asInt(json['place_id']),
    name: JsonReader.asString(json['name']),
    kind: JsonReader.asString(json['kind']),
    stateName: JsonReader.asString(json['state_name']),
    latitude: JsonReader.asDouble(json['latitude']),
    longitude: JsonReader.asDouble(json['longitude']),
    zoom: JsonReader.asDoubleOrNull(json['zoom']),
    aliases: JsonReader.asStringOrNull(json['aliases']),
  );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'place_id': placeId,
    'name': name,
    'kind': kind,
    'state_name': stateName,
    'latitude': latitude,
    'longitude': longitude,
    'zoom': zoom,
    'aliases': aliases,
  };

  /// Data model -> domain model. Called by `MapRepository`, nowhere else.
  MapPlace toDomain() => MapPlace(
    name: name,
    kind: _kind(kind),
    stateName: stateName,
    latitude: latitude,
    longitude: longitude,
    zoom: zoom ?? _defaultZoom(_kind(kind)),
    aliases: (aliases ?? '')
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false),
  );

  static MapPlaceKind _kind(String value) => switch (value.toLowerCase()) {
    'landmark' => MapPlaceKind.landmark,
    'area' => MapPlaceKind.area,
    'town' => MapPlaceKind.town,
    _ => MapPlaceKind.city,
  };

  /// Used when a row leaves `zoom` null - a landmark wants a closer look than
  /// a whole city.
  static double _defaultZoom(MapPlaceKind kind) => switch (kind) {
    MapPlaceKind.landmark => 16,
    MapPlaceKind.area => 15,
    MapPlaceKind.town => 13,
    MapPlaceKind.city => 13,
  };
}
