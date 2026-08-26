import '../../core/json_model.dart';
import '../../domain_model/region.dart';

/// The 13 states and 3 federal territories of Malaysia (REQ102_1).
///
/// Not a database table. The live schema has no state column on `restaurant`
/// or `submitted_landmark` and no PostGIS, so a state cannot be read off a
/// row - REQ102_15 needs the boundaries to exist somewhere, and this is that
/// somewhere. `MapRepository` is the only reader; it converts each entry into
/// a `Region` and nothing above ever sees this class.
///
/// **The outlines are deliberate approximations.** Each boundary is a coarse
/// polygon of 4-16 vertices, accurate enough to identify a state on a phone
/// screen and to decide which state a restaurant's coordinates fall in, but
/// it is not a survey boundary - coastlines and enclaves are simplified away.
/// Swap [catalogue] for a real GeoJSON asset when boundary precision starts
/// to matter; nothing above `MapRepository` changes when you do.
class MalaysiaRegionDataModel implements JsonModel {
  const MalaysiaRegionDataModel({
    required this.code,
    required this.name,
    required this.centreLatitude,
    required this.centreLongitude,
    required this.defaultZoom,
    required this.boundary,
    required this.places,
  });

  final String code;
  final String name;
  final double centreLatitude;
  final double centreLongitude;
  final double defaultZoom;

  /// Closed outline as `[latitude, longitude]` pairs.
  final List<List<double>> boundary;

  final List<MalaysiaPlaceDataModel> places;

  factory MalaysiaRegionDataModel.fromJson(Map<String, dynamic> json) {
    return MalaysiaRegionDataModel(
      code: JsonReader.asString(json['code']),
      name: JsonReader.asString(json['name']),
      centreLatitude: JsonReader.asDouble(json['centre_latitude']),
      centreLongitude: JsonReader.asDouble(json['centre_longitude']),
      defaultZoom: JsonReader.asDouble(json['default_zoom'], fallback: 9),
      boundary: _boundaryFromJson(json['boundary']),
      places: JsonReader.asModelList<MalaysiaPlaceDataModel>(
        json['places'],
        MalaysiaPlaceDataModel.fromJson,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'name': name,
    'centre_latitude': centreLatitude,
    'centre_longitude': centreLongitude,
    'default_zoom': defaultZoom,
    'boundary': boundary,
    'places': places
        .map((MalaysiaPlaceDataModel p) => p.toJson())
        .toList(growable: false),
  };

  /// Data model -> domain model. Called by `MapRepository`, nowhere else.
  Region toDomain() => Region(
    code: code,
    name: name,
    centreLatitude: centreLatitude,
    centreLongitude: centreLongitude,
    defaultZoom: defaultZoom,
    boundary: boundary
        .map((List<double> point) => GeoPoint(point[0], point[1]))
        .toList(growable: false),
    places: places
        .map((MalaysiaPlaceDataModel place) => place.toDomain(name))
        .toList(growable: false),
  );

  // ===========================================================================
  // The catalogue (REQ102_1)
  // ===========================================================================
  //
  // 13 states + 3 federal territories, north to south down the peninsula and
  // then east across Borneo. `defaultZoom` is where the map settles when the
  // state is selected from the heatmap or a search result (REQ102_22); every
  // value is above `MapExplorationLogic.detailedViewZoom`, so picking a state
  // always lands the tourist in the detailed map view (UC300 BF-5).

  static const List<MalaysiaRegionDataModel> catalogue =
      <MalaysiaRegionDataModel>[
        MalaysiaRegionDataModel(
          code: 'PLS',
          name: 'Perlis',
          centreLatitude: 6.51,
          centreLongitude: 100.26,
          defaultZoom: 11,
          boundary: <List<double>>[
            <double>[6.72, 100.11],
            <double>[6.68, 100.3],
            <double>[6.55, 100.42],
            <double>[6.44, 100.38],
            <double>[6.38, 100.22],
            <double>[6.4, 100.12],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Kangar', 6.4414, 100.1986),
            MalaysiaPlaceDataModel('Arau', 6.4300, 100.2700),
            MalaysiaPlaceDataModel('Padang Besar', 6.6600, 100.3200),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'KDH',
          name: 'Kedah',
          centreLatitude: 6.06,
          centreLongitude: 100.58,
          defaultZoom: 9.2,
          boundary: <List<double>>[
            <double>[6.55, 100.42],
            <double>[6.7, 100.65],
            <double>[6.55, 100.95],
            <double>[6.3, 101.05],
            <double>[6.05, 100.98],
            <double>[5.75, 100.92],
            <double>[5.5, 100.72],
            <double>[5.42, 100.55],
            <double>[5.5, 100.36],
            <double>[5.57, 100.38],
            <double>[5.8, 100.35],
            <double>[6.1, 100.3],
            <double>[6.4, 100.12],
            <double>[6.38, 100.22],
            <double>[6.44, 100.38],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Alor Setar', 6.1248, 100.3678),
            MalaysiaPlaceDataModel('Sungai Petani', 5.6470, 100.4870),
            MalaysiaPlaceDataModel('Langkawi', 6.3500, 99.8000),
            MalaysiaPlaceDataModel('Kulim', 5.3650, 100.5610),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'PNG',
          name: 'Pulau Pinang',
          centreLatitude: 5.37,
          centreLongitude: 100.32,
          defaultZoom: 10.8,
          boundary: <List<double>>[
            <double>[5.5, 100.36],
            <double>[5.42, 100.55],
            <double>[5.28, 100.55],
            <double>[5.14, 100.45],
            <double>[5.19, 100.2],
            <double>[5.35, 100.17],
            <double>[5.47, 100.28],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('George Town', 5.4141, 100.3288),
            MalaysiaPlaceDataModel('Butterworth', 5.3991, 100.3638),
            MalaysiaPlaceDataModel('Bayan Lepas', 5.2945, 100.2670),
            MalaysiaPlaceDataModel('Balik Pulau', 5.3500, 100.2330),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'PRK',
          name: 'Perak',
          centreLatitude: 4.65,
          centreLongitude: 101.10,
          defaultZoom: 8.7,
          boundary: <List<double>>[
            <double>[5.5, 100.72],
            <double>[5.75, 100.92],
            <double>[6.05, 100.98],
            <double>[6.3, 101.05],
            <double>[6.05, 101.28],
            <double>[5.95, 101.3],
            <double>[5.55, 101.38],
            <double>[5.1, 101.58],
            <double>[4.62, 101.55],
            <double>[4.2, 101.45],
            <double>[3.95, 101.3],
            <double>[3.7, 101.45],
            <double>[3.8, 101.1],
            <double>[3.75, 100.95],
            <double>[3.98, 100.78],
            <double>[4.35, 100.6],
            <double>[4.85, 100.58],
            <double>[5.05, 100.48],
            <double>[5.14, 100.45],
            <double>[5.28, 100.55],
            <double>[5.42, 100.55],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Ipoh', 4.5975, 101.0901),
            MalaysiaPlaceDataModel('Taiping', 4.8500, 100.7333),
            MalaysiaPlaceDataModel('Teluk Intan', 4.0259, 101.0210),
            MalaysiaPlaceDataModel('Lumut', 4.2300, 100.6300),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'KTN',
          name: 'Kelantan',
          centreLatitude: 5.45,
          centreLongitude: 102.05,
          defaultZoom: 8.9,
          boundary: <List<double>>[
            <double>[6.25, 102.1],
            <double>[6.2, 102.3],
            <double>[5.85, 102.55],
            <double>[5.5, 102.45],
            <double>[5.05, 102.3],
            <double>[4.7, 102.05],
            <double>[4.55, 101.8],
            <double>[4.62, 101.55],
            <double>[5.1, 101.58],
            <double>[5.55, 101.38],
            <double>[5.95, 101.3],
            <double>[6.05, 101.55],
            <double>[6.15, 101.85],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Kota Bharu', 6.1254, 102.2381),
            MalaysiaPlaceDataModel('Pasir Mas', 6.0400, 102.1400),
            MalaysiaPlaceDataModel('Kuala Krai', 5.5300, 102.2000),
            MalaysiaPlaceDataModel('Gua Musang', 4.8800, 101.9600),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'TRG',
          name: 'Terengganu',
          centreLatitude: 5.05,
          centreLongitude: 103.00,
          defaultZoom: 8.9,
          boundary: <List<double>>[
            <double>[5.85, 102.55],
            <double>[5.75, 102.75],
            <double>[5.33, 103.14],
            <double>[4.78, 103.42],
            <double>[4.3, 103.45],
            <double>[4.2, 103.3],
            <double>[4.35, 102.9],
            <double>[4.7, 102.6],
            <double>[5.05, 102.3],
            <double>[5.5, 102.45],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Kuala Terengganu', 5.3302, 103.1408),
            MalaysiaPlaceDataModel('Kemaman', 4.2300, 103.4200),
            MalaysiaPlaceDataModel('Dungun', 4.7600, 103.4200),
            MalaysiaPlaceDataModel('Pulau Redang', 5.7800, 103.0100),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'PHG',
          name: 'Pahang',
          centreLatitude: 3.75,
          centreLongitude: 102.55,
          defaultZoom: 8.5,
          boundary: <List<double>>[
            <double>[4.62, 101.55],
            <double>[4.55, 101.8],
            <double>[4.7, 102.05],
            <double>[5.05, 102.3],
            <double>[4.7, 102.6],
            <double>[4.35, 102.9],
            <double>[4.2, 103.3],
            <double>[4.3, 103.45],
            <double>[4.13, 103.4],
            <double>[3.82, 103.33],
            <double>[3.49, 103.4],
            <double>[2.95, 103.45],
            <double>[2.8, 103.5],
            <double>[2.65, 103.62],
            <double>[2.65, 103.3],
            <double>[2.75, 102.9],
            <double>[3.02, 102.62],
            <double>[3.02, 102.18],
            <double>[2.85, 101.78],
            <double>[3.05, 101.92],
            <double>[3.35, 101.85],
            <double>[3.7, 101.45],
            <double>[3.95, 101.3],
            <double>[4.2, 101.45],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Kuantan', 3.8077, 103.3260),
            MalaysiaPlaceDataModel('Cameron Highlands', 4.4711, 101.3771),
            MalaysiaPlaceDataModel('Temerloh', 3.4500, 102.4200),
            MalaysiaPlaceDataModel('Bentong', 3.5200, 101.9100),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'SGR',
          name: 'Selangor',
          centreLatitude: 3.20,
          centreLongitude: 101.45,
          defaultZoom: 9.6,
          boundary: <List<double>>[
            <double>[3.75, 100.95],
            <double>[3.8, 101.1],
            <double>[3.7, 101.45],
            <double>[3.35, 101.85],
            <double>[3.05, 101.92],
            <double>[2.85, 101.78],
            <double>[2.58, 101.66],
            <double>[3.0, 101.32],
            <double>[3.35, 101.25],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Shah Alam', 3.0733, 101.5185),
            MalaysiaPlaceDataModel('Petaling Jaya', 3.1073, 101.6067),
            MalaysiaPlaceDataModel('Klang', 3.0449, 101.4455),
            MalaysiaPlaceDataModel('Subang Jaya', 3.0567, 101.5851),
            MalaysiaPlaceDataModel('Kajang', 2.9930, 101.7880),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'KUL',
          name: 'Kuala Lumpur',
          centreLatitude: 3.139,
          centreLongitude: 101.687,
          defaultZoom: 12,
          boundary: <List<double>>[
            <double>[3.235, 101.625],
            <double>[3.235, 101.75],
            <double>[3.055, 101.75],
            <double>[3.055, 101.625],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Bukit Bintang', 3.1466, 101.7113),
            MalaysiaPlaceDataModel('Chow Kit', 3.1650, 101.6970),
            MalaysiaPlaceDataModel('Cheras', 3.1000, 101.7500),
            MalaysiaPlaceDataModel('Bangsar', 3.1300, 101.6700),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'PJY',
          name: 'Putrajaya',
          centreLatitude: 2.926,
          centreLongitude: 101.696,
          defaultZoom: 12.5,
          boundary: <List<double>>[
            <double>[2.965, 101.665],
            <double>[2.965, 101.725],
            <double>[2.895, 101.725],
            <double>[2.895, 101.665],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Putrajaya', 2.9264, 101.6964),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'NSN',
          name: 'Negeri Sembilan',
          centreLatitude: 2.73,
          centreLongitude: 102.05,
          defaultZoom: 9.7,
          boundary: <List<double>>[
            <double>[2.85, 101.78],
            <double>[3.02, 102.18],
            <double>[3.02, 102.62],
            <double>[2.6, 102.6],
            <double>[2.42, 102.42],
            <double>[2.3, 102.12],
            <double>[2.48, 101.76],
            <double>[2.58, 101.66],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Seremban', 2.7297, 101.9381),
            MalaysiaPlaceDataModel('Port Dickson', 2.5228, 101.7960),
            MalaysiaPlaceDataModel('Nilai', 2.8100, 101.7900),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'MLK',
          name: 'Melaka',
          centreLatitude: 2.30,
          centreLongitude: 102.25,
          defaultZoom: 10.6,
          boundary: <List<double>>[
            <double>[2.42, 102.42],
            <double>[2.3, 102.12],
            <double>[2.16, 102.2],
            <double>[2.02, 102.52],
            <double>[2.28, 102.62],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Melaka City', 2.1896, 102.2501),
            MalaysiaPlaceDataModel('Ayer Keroh', 2.2700, 102.2900),
            MalaysiaPlaceDataModel('Alor Gajah', 2.3800, 102.2100),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'JHR',
          name: 'Johor',
          centreLatitude: 1.85,
          centreLongitude: 103.35,
          defaultZoom: 8.7,
          boundary: <List<double>>[
            <double>[2.6, 102.6],
            <double>[3.02, 102.62],
            <double>[2.75, 102.9],
            <double>[2.65, 103.3],
            <double>[2.65, 103.62],
            <double>[2.43, 103.84],
            <double>[1.85, 104.15],
            <double>[1.55, 104.27],
            <double>[1.36, 104.1],
            <double>[1.46, 103.76],
            <double>[1.26, 103.51],
            <double>[1.48, 103.39],
            <double>[1.83, 102.9],
            <double>[2.02, 102.52],
            <double>[2.28, 102.62],
            <double>[2.42, 102.42],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Johor Bahru', 1.4927, 103.7414),
            MalaysiaPlaceDataModel('Batu Pahat', 1.8548, 102.9325),
            MalaysiaPlaceDataModel('Muar', 2.0442, 102.5689),
            MalaysiaPlaceDataModel('Kluang', 2.0250, 103.3167),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'LBN',
          name: 'Labuan',
          centreLatitude: 5.28,
          centreLongitude: 115.23,
          defaultZoom: 11.5,
          boundary: <List<double>>[
            <double>[5.345, 115.175],
            <double>[5.335, 115.265],
            <double>[5.245, 115.265],
            <double>[5.235, 115.18],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Victoria', 5.2767, 115.2417),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'SBH',
          name: 'Sabah',
          centreLatitude: 5.60,
          centreLongitude: 117.10,
          defaultZoom: 8.2,
          boundary: <List<double>>[
            <double>[5.02, 115.05],
            <double>[5.1, 115.52],
            <double>[5.38, 115.78],
            <double>[5.75, 115.95],
            <double>[5.98, 116.07],
            <double>[6.2, 116.25],
            <double>[6.42, 116.48],
            <double>[6.75, 116.72],
            <double>[7.03, 116.78],
            <double>[6.95, 117.02],
            <double>[6.65, 117.05],
            <double>[6.55, 117.42],
            <double>[6.2, 117.55],
            <double>[5.9, 118.05],
            <double>[5.45, 118.55],
            <double>[5.32, 119.15],
            <double>[5.02, 118.85],
            <double>[4.85, 118.3],
            <double>[4.62, 118.62],
            <double>[4.42, 118.72],
            <double>[4.25, 117.95],
            <double>[4.32, 117.3],
            <double>[4.25, 116.7],
            <double>[4.45, 116.2],
            <double>[4.62, 115.6],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Kota Kinabalu', 5.9804, 116.0735),
            MalaysiaPlaceDataModel('Sandakan', 5.8402, 118.1179),
            MalaysiaPlaceDataModel('Tawau', 4.2448, 117.8912),
            MalaysiaPlaceDataModel('Semporna', 4.4800, 118.6100),
          ],
        ),
        MalaysiaRegionDataModel(
          code: 'SWK',
          name: 'Sarawak',
          centreLatitude: 2.60,
          centreLongitude: 112.60,
          defaultZoom: 7.8,
          boundary: <List<double>>[
            <double>[2.05, 109.64],
            <double>[1.75, 110.32],
            <double>[1.72, 110.78],
            <double>[1.92, 111.22],
            <double>[2.15, 111.45],
            <double>[2.58, 111.62],
            <double>[2.82, 112.12],
            <double>[3.06, 112.72],
            <double>[3.26, 113.1],
            <double>[3.76, 113.7],
            <double>[4.1, 113.86],
            <double>[4.42, 114.0],
            <double>[4.62, 114.22],
            <double>[4.86, 114.76],
            <double>[5.02, 115.05],
            <double>[4.62, 115.6],
            <double>[4.1, 115.45],
            <double>[3.58, 115.08],
            <double>[3.02, 114.78],
            <double>[2.4, 114.28],
            <double>[1.95, 113.68],
            <double>[1.55, 113.1],
            <double>[1.38, 112.48],
            <double>[1.12, 111.88],
            <double>[1.02, 111.28],
            <double>[0.85, 110.7],
            <double>[0.95, 110.1],
            <double>[1.55, 109.62],
          ],
          places: <MalaysiaPlaceDataModel>[
            MalaysiaPlaceDataModel('Kuching', 1.5533, 110.3592),
            MalaysiaPlaceDataModel('Miri', 4.3995, 113.9914),
            MalaysiaPlaceDataModel('Sibu', 2.2870, 111.8305),
            MalaysiaPlaceDataModel('Bintulu', 3.1700, 113.0400),
          ],
        ),
      ];

  static List<List<double>> _boundaryFromJson(Object? raw) {
    if (raw is! List) return const <List<double>>[];
    return raw
        .whereType<List<Object?>>()
        .map(
          (List<Object?> pair) => pair
              .whereType<num>()
              .map((num value) => value.toDouble())
              .toList(growable: false),
        )
        .where((List<double> pair) => pair.length == 2)
        .toList(growable: false);
  }
}

/// A city or notable location inside a state (REQ102_19).
class MalaysiaPlaceDataModel implements JsonModel {
  const MalaysiaPlaceDataModel(this.name, this.latitude, this.longitude);

  final String name;
  final double latitude;
  final double longitude;

  factory MalaysiaPlaceDataModel.fromJson(Map<String, dynamic> json) =>
      MalaysiaPlaceDataModel(
        JsonReader.asString(json['name']),
        JsonReader.asDouble(json['latitude']),
        JsonReader.asDouble(json['longitude']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
  };

  RegionPlace toDomain(String regionName) => RegionPlace(
    name: name,
    regionName: regionName,
    latitude: latitude,
    longitude: longitude,
  );
}
