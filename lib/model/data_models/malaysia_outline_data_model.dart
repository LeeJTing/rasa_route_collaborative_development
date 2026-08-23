import '../../core/json_model.dart';
import '../../domain_model/region.dart';

/// The coastline of Malaysia as three closed rings - one per landmass.
///
/// REQ102_1 says the map covers **only** Malaysia. On the painted overview
/// that is automatic, but the detailed map view is real OpenStreetMap, which
/// of course renders Thailand, Singapore, Brunei and Kalimantan too. These
/// rings are what hides them: the detailed view draws one polygon over the
/// whole world with these cut out of it, so the tiles only show through inside
/// the country.
///
/// Every vertex here is copied from the state outlines in
/// [MalaysiaRegionDataModel.catalogue] - the peninsula ring walks the Thai
/// border, down the east coast and back up the west; the Borneo ring walks
/// Sarawak's coast into Sabah's, round the top, and back along the Kalimantan
/// border. Because the coordinates are shared rather than recomputed, the mask
/// lines up with the heatmap exactly.
///
/// **Change a coastal state boundary and you must change the matching vertex
/// here**, or a sliver of Malaysia will end up masked out.
///
/// The mask is only drawn below `MapExplorationLogic.countryMaskMaxZoom`.
/// These rings are far too coarse for street level - left on, they would hide
/// real Malaysian roads near the coast.
class MalaysiaOutlineDataModel implements JsonModel {
  const MalaysiaOutlineDataModel(this.name, this.ring);

  final String name;

  /// Closed outline as `[latitude, longitude]` pairs.
  final List<List<double>> ring;

  factory MalaysiaOutlineDataModel.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['ring'];
    return MalaysiaOutlineDataModel(
      JsonReader.asString(json['name']),
      raw is! List
          ? const <List<double>>[]
          : raw
                .whereType<List<Object?>>()
                .map(
                  (List<Object?> pair) => pair
                      .whereType<num>()
                      .map((num value) => value.toDouble())
                      .toList(growable: false),
                )
                .where((List<double> pair) => pair.length == 2)
                .toList(growable: false),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'ring': ring,
  };

  /// Data model -> domain model. Called by `MapRepository`, nowhere else.
  CountryOutline toDomain() => CountryOutline(
    name: name,
    ring: ring
        .map((List<double> point) => GeoPoint(point[0], point[1]))
        .toList(growable: false),
  );

  static const List<MalaysiaOutlineDataModel> catalogue =
      <MalaysiaOutlineDataModel>[
        // --- Peninsular Malaysia ------------------------------------------
        // Thai border west to east, down the east coast to Johor, back up the
        // west coast. The Penang bulge is part of the run, as it is in the
        // state outlines.
        MalaysiaOutlineDataModel('Peninsular Malaysia', <List<double>>[
          <double>[6.72, 100.11],
          <double>[6.68, 100.30],
          <double>[6.55, 100.42],
          <double>[6.70, 100.65],
          <double>[6.55, 100.95],
          <double>[6.30, 101.05],
          <double>[6.05, 101.28],
          <double>[5.95, 101.30],
          <double>[6.05, 101.55],
          <double>[6.15, 101.85],
          <double>[6.25, 102.10],
          <double>[6.20, 102.30],
          <double>[5.85, 102.55],
          <double>[5.75, 102.75],
          <double>[5.33, 103.14],
          <double>[4.78, 103.42],
          <double>[4.30, 103.45],
          <double>[4.13, 103.40],
          <double>[3.82, 103.33],
          <double>[3.49, 103.40],
          <double>[2.95, 103.45],
          <double>[2.80, 103.50],
          <double>[2.65, 103.62],
          <double>[2.43, 103.84],
          <double>[1.85, 104.15],
          <double>[1.55, 104.27],
          <double>[1.36, 104.10],
          <double>[1.46, 103.76],
          <double>[1.26, 103.51],
          <double>[1.48, 103.39],
          <double>[1.83, 102.90],
          <double>[2.02, 102.52],
          <double>[2.16, 102.20],
          <double>[2.30, 102.12],
          <double>[2.48, 101.76],
          <double>[2.58, 101.66],
          <double>[3.00, 101.32],
          <double>[3.35, 101.25],
          <double>[3.75, 100.95],
          <double>[3.98, 100.78],
          <double>[4.35, 100.60],
          <double>[4.85, 100.58],
          <double>[5.05, 100.48],
          <double>[5.14, 100.45],
          <double>[5.19, 100.20],
          <double>[5.35, 100.17],
          <double>[5.47, 100.28],
          <double>[5.50, 100.36],
          <double>[5.57, 100.38],
          <double>[5.80, 100.35],
          <double>[6.10, 100.30],
          <double>[6.40, 100.12],
        ]),

        // --- Borneo: Sarawak and Sabah as one landmass ---------------------
        // Sarawak's coast north-east into Sabah's, round the northern tip and
        // the eastern lobes, then back south-west along the Kalimantan border.
        MalaysiaOutlineDataModel('Borneo', <List<double>>[
          <double>[2.05, 109.64],
          <double>[1.75, 110.32],
          <double>[1.72, 110.78],
          <double>[1.92, 111.22],
          <double>[2.15, 111.45],
          <double>[2.58, 111.62],
          <double>[2.82, 112.12],
          <double>[3.06, 112.72],
          <double>[3.26, 113.10],
          <double>[3.76, 113.70],
          <double>[4.10, 113.86],
          <double>[4.42, 114.00],
          <double>[4.62, 114.22],
          <double>[4.86, 114.76],
          <double>[5.02, 115.05],
          <double>[5.10, 115.52],
          <double>[5.38, 115.78],
          <double>[5.75, 115.95],
          <double>[5.98, 116.07],
          <double>[6.20, 116.25],
          <double>[6.42, 116.48],
          <double>[6.75, 116.72],
          <double>[7.03, 116.78],
          <double>[6.95, 117.02],
          <double>[6.65, 117.05],
          <double>[6.55, 117.42],
          <double>[6.20, 117.55],
          <double>[5.90, 118.05],
          <double>[5.45, 118.55],
          <double>[5.32, 119.15],
          <double>[5.02, 118.85],
          <double>[4.85, 118.30],
          <double>[4.62, 118.62],
          <double>[4.42, 118.72],
          <double>[4.25, 117.95],
          <double>[4.32, 117.30],
          <double>[4.25, 116.70],
          <double>[4.45, 116.20],
          <double>[4.62, 115.60],
          <double>[4.10, 115.45],
          <double>[3.58, 115.08],
          <double>[3.02, 114.78],
          <double>[2.40, 114.28],
          <double>[1.95, 113.68],
          <double>[1.55, 113.10],
          <double>[1.38, 112.48],
          <double>[1.12, 111.88],
          <double>[1.02, 111.28],
          <double>[0.85, 110.70],
          <double>[0.95, 110.10],
          <double>[1.55, 109.62],
        ]),

        // --- Labuan --------------------------------------------------------
        MalaysiaOutlineDataModel('Labuan', <List<double>>[
          <double>[5.345, 115.175],
          <double>[5.335, 115.265],
          <double>[5.245, 115.265],
          <double>[5.235, 115.180],
        ]),
      ];

  // ===========================================================================
  // The mask rings (REQ102_1)
  // ===========================================================================
  //
  // [catalogue] traces the coastline tightly, which is what the painted
  // overview clips to. Masking the *detailed* map with those same rings was
  // wrong twice over: they are coarse, so they cut real Malaysian land, and
  // they treated every island as its own cut-out - so the strait between
  // Penang island and Butterworth came back as a cream stripe through the
  // middle of George Town.
  //
  // These are **two continuous rings**, one per landmass. Each is the tight
  // coastline plus its offshore islands (Langkawi, Penang, Pangkor, Redang and
  // Perhentian, Tioman; Labuan on the Borneo side), pushed out 0.12 degrees
  // (~13 km) and then morphologically closed, which bridges the water between
  // an island and its mainland. The result: sail from Butterworth to George
  // Town and the map stays continuous.
  //
  // West and East Malaysia are deliberately left as separate rings. The South
  // China Sea between them is 5 degrees wide and genuinely is not Malaysia.
  //
  // Erring outward is the right way to be wrong here: a strip of southern
  // Thailand at the border is a much smaller problem than a missing Malaysian
  // island. Two neighbours cannot be masked at any buffer and stay visible on
  // purpose - Singapore sits a kilometre across the causeway from Johor, and
  // Brunei is enclaved inside Sarawak.
  static const List<MalaysiaOutlineDataModel> maskCatalogue =
      <MalaysiaOutlineDataModel>[
        MalaysiaOutlineDataModel('Peninsular Malaysia and its islands', <List<double>>[
          <double>[6.112, 99.462],
          <double>[6.600, 99.491],
          <double>[6.664, 99.869],
          <double>[6.840, 100.117],
          <double>[6.772, 100.429],
          <double>[6.817, 100.677],
          <double>[6.659, 101.000],
          <double>[6.345, 101.173],
          <double>[6.175, 101.393],
          <double>[6.173, 101.536],
          <double>[6.369, 102.111],
          <double>[6.305, 102.357],
          <double>[6.132, 102.575],
          <double>[6.080, 103.209],
          <double>[5.439, 103.224],
          <double>[4.792, 103.539],
          <double>[4.292, 103.570],
          <double>[3.819, 103.460],
          <double>[3.216, 103.558],
          <double>[3.036, 103.768],
          <double>[3.070, 104.304],
          <double>[2.979, 104.416],
          <double>[2.580, 104.413],
          <double>[2.411, 104.196],
          <double>[2.250, 104.130],
          <double>[1.553, 104.390],
          <double>[1.277, 104.186],
          <double>[1.240, 104.096],
          <double>[1.290, 103.794],
          <double>[1.151, 103.560],
          <double>[1.152, 103.459],
          <double>[1.422, 103.263],
          <double>[1.713, 102.857],
          <double>[2.058, 102.137],
          <double>[2.218, 102.002],
          <double>[2.492, 101.578],
          <double>[2.939, 101.217],
          <double>[3.354, 101.097],
          <double>[3.931, 100.666],
          <double>[4.099, 100.392],
          <double>[4.318, 100.382],
          <double>[4.541, 100.470],
          <double>[4.798, 100.456],
          <double>[4.965, 100.351],
          <double>[5.042, 100.089],
          <double>[5.110, 100.027],
          <double>[5.504, 100.020],
          <double>[5.710, 100.076],
          <double>[5.851, 100.041],
          <double>[5.987, 99.891],
          <double>[6.014, 99.551],
        ]),
        MalaysiaOutlineDataModel('Borneo and Labuan', <List<double>>[
          <double>[1.536, 109.501],
          <double>[2.059, 109.520],
          <double>[2.155, 109.582],
          <double>[2.161, 109.684],
          <double>[1.873, 110.350],
          <double>[1.862, 110.799],
          <double>[2.010, 111.125],
          <double>[2.173, 111.304],
          <double>[2.680, 111.554],
          <double>[3.381, 113.057],
          <double>[3.840, 113.597],
          <double>[4.485, 113.899],
          <double>[4.712, 114.143],
          <double>[5.090, 114.925],
          <double>[5.449, 115.116],
          <double>[5.404, 115.490],
          <double>[5.485, 115.672],
          <double>[6.052, 115.974],
          <double>[6.775, 116.588],
          <double>[7.139, 116.731],
          <double>[7.045, 117.093],
          <double>[6.764, 117.231],
          <double>[6.626, 117.513],
          <double>[6.261, 117.692],
          <double>[5.992, 118.127],
          <double>[5.594, 118.572],
          <double>[5.432, 119.192],
          <double>[5.359, 119.263],
          <double>[5.249, 119.246],
          <double>[4.787, 118.796],
          <double>[4.642, 118.769],
          <double>[4.413, 118.840],
          <double>[4.304, 118.750],
          <double>[4.130, 117.957],
          <double>[4.197, 117.301],
          <double>[4.130, 116.696],
          <double>[4.397, 115.941],
          <double>[4.349, 115.717],
          <double>[2.948, 114.876],
          <double>[2.322, 114.371],
          <double>[1.436, 113.137],
          <double>[1.272, 112.540],
          <double>[1.003, 111.905],
          <double>[0.730, 110.696],
          <double>[0.854, 110.029],
        ]),
      ];
}
