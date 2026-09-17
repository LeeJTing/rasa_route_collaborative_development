import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/map_place.dart';
import 'package:rasa_route_collaborative_development/model/data_models/malaysia_outline_data_model.dart';
import 'package:rasa_route_collaborative_development/model/data_models/malaysia_region_data_model.dart';
import 'package:rasa_route_collaborative_development/model/data_models/place_data_model.dart';
import 'package:rasa_route_collaborative_development/model/repositories/map_repository.dart';

void main() {
  test('outline conversion preserves name and coordinate ordering', () {
    const MalaysiaOutlineDataModel data = MalaysiaOutlineDataModel(
      'Test outline',
      <List<double>>[
        <double>[1.25, 101.5],
        <double>[2.75, 102.5],
      ],
    );

    final outline = MapRepository.outlineFromDataModel(data);

    expect(outline.name, 'Test outline');
    expect(outline.ring.length, 2);
    expect(outline.ring[0].latitude, 1.25);
    expect(outline.ring[0].longitude, 101.5);
    expect(outline.ring[1].latitude, 2.75);
    expect(outline.ring[1].longitude, 102.5);
  });

  test('region conversion preserves boundary and place ordering', () {
    const MalaysiaRegionDataModel data = MalaysiaRegionDataModel(
      code: 'TST',
      name: 'Test State',
      centreLatitude: 3,
      centreLongitude: 102,
      defaultZoom: 9,
      boundary: <List<double>>[
        <double>[1, 101],
        <double>[2, 102],
      ],
      places: <MalaysiaPlaceDataModel>[
        MalaysiaPlaceDataModel('First', 3, 103),
        MalaysiaPlaceDataModel('Second', 4, 104),
      ],
    );

    final region = MapRepository.regionFromDataModel(data);

    expect(region.code, 'TST');
    expect(region.boundary.map((point) => point.latitude), <double>[1, 2]);
    expect(region.places.map((place) => place.name), <String>[
      'First',
      'Second',
    ]);
    expect(
      region.places.every((place) => place.regionName == 'Test State'),
      isTrue,
    );
  });

  test('place conversion keeps aliases and landmark default zoom', () {
    const PlaceDataModel data = PlaceDataModel(
      placeId: 1,
      name: 'Test Place',
      kind: 'landmark',
      stateName: 'Test State',
      latitude: 3,
      longitude: 102,
      aliases: ' One, ,Two ',
    );

    final MapPlace place = MapRepository.placeFromDataModel(data);

    expect(place.kind, MapPlaceKind.landmark);
    expect(place.zoom, 16);
    expect(place.aliases, <String>['One', 'Two']);
  });

  test('unknown place kind retains the city fallback and explicit zoom', () {
    const PlaceDataModel data = PlaceDataModel(
      placeId: 2,
      name: 'Unknown Kind',
      kind: 'unexpected',
      stateName: 'Test State',
      latitude: 3,
      longitude: 102,
      zoom: 11.5,
    );

    final MapPlace place = MapRepository.placeFromDataModel(data);

    expect(place.kind, MapPlaceKind.city);
    expect(place.zoom, 11.5);
    expect(place.aliases, isEmpty);
  });
}
