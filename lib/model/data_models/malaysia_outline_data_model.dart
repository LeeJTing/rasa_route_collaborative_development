import '../../core/json_model.dart';

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
  // overview clips its blur to. Using those same rings to mask the *detailed*
  // map turned out to be wrong: they are coarse, so they cut real Malaysian
  // land - Langkawi and Tioman vanished entirely, and river mouths and bays
  // were shaved off.
  //
  // These rings are the tight ones pushed out by 0.12 degrees (~13 km), plus
  // the islands the coastline had erased. Erring outward is the right way to be
  // wrong here: a strip of southern Thailand at the border is a much smaller
  // problem than a missing Malaysian island.
  //
  // Two neighbours cannot be masked at any buffer and are deliberately left
  // visible: Singapore sits a kilometre across the causeway from Johor, and
  // Brunei is enclaved inside Sarawak. Hiding either would mean cutting
  // Malaysian land.
  static const List<MalaysiaOutlineDataModel> maskCatalogue =
      <MalaysiaOutlineDataModel>[
        MalaysiaOutlineDataModel('Peninsular Malaysia', <List<double>>[
          <double>[6.716, 99.990],
          <double>[6.812, 100.033],
          <double>[6.837, 100.135],
          <double>[6.797, 100.325],
          <double>[6.706, 100.439],
          <double>[6.801, 100.584],
          <double>[6.807, 100.704],
          <double>[6.657, 101.004],
          <double>[6.365, 101.153],
          <double>[6.111, 101.379],
          <double>[6.361, 102.055],
          <double>[6.316, 102.329],
          <double>[5.944, 102.630],
          <double>[5.832, 102.838],
          <double>[5.412, 103.228],
          <double>[4.787, 103.540],
          <double>[4.307, 103.570],
          <double>[3.819, 103.453],
          <double>[2.975, 103.568],
          <double>[2.858, 103.607],
          <double>[2.487, 103.946],
          <double>[1.595, 104.381],
          <double>[1.470, 104.359],
          <double>[1.280, 104.189],
          <double>[1.245, 104.066],
          <double>[1.327, 103.786],
          <double>[1.166, 103.585],
          <double>[1.142, 103.486],
          <double>[1.203, 103.405],
          <double>[1.398, 103.298],
          <double>[1.727, 102.838],
          <double>[2.050, 102.152],
          <double>[2.209, 102.034],
          <double>[2.395, 101.675],
          <double>[2.924, 101.227],
          <double>[3.300, 101.138],
          <double>[3.909, 100.683],
          <double>[4.298, 100.492],
          <double>[4.819, 100.461],
          <double>[5.036, 100.358],
          <double>[5.072, 100.176],
          <double>[5.168, 100.082],
          <double>[5.431, 100.082],
          <double>[5.589, 100.256],
          <double>[6.058, 100.185],
          <double>[6.396, 100.000],
        ]),
        MalaysiaOutlineDataModel('Borneo', <List<double>>[
          <double>[2.055, 109.520],
          <double>[2.152, 109.576],
          <double>[2.160, 109.688],
          <double>[1.868, 110.349],
          <double>[1.842, 110.758],
          <double>[2.020, 111.151],
          <double>[2.217, 111.348],
          <double>[2.688, 111.568],
          <double>[3.360, 113.033],
          <double>[3.835, 113.603],
          <double>[4.468, 113.890],
          <double>[4.709, 114.139],
          <double>[5.125, 114.992],
          <double>[5.211, 115.460],
          <double>[5.448, 115.679],
          <double>[6.056, 115.977],
          <double>[6.800, 116.608],
          <double>[7.134, 116.720],
          <double>[7.064, 117.058],
          <double>[6.962, 117.139],
          <double>[6.744, 117.161],
          <double>[6.666, 117.451],
          <double>[6.592, 117.532],
          <double>[6.281, 117.648],
          <double>[5.989, 118.130],
          <double>[5.561, 118.607],
          <double>[5.392, 119.246],
          <double>[5.235, 119.235],
          <double>[4.935, 118.935],
          <double>[4.807, 118.566],
          <double>[4.674, 118.727],
          <double>[4.474, 118.827],
          <double>[4.368, 118.828],
          <double>[4.303, 118.746],
          <double>[4.133, 117.976],
          <double>[4.199, 117.301],
          <double>[4.131, 116.714],
          <double>[4.472, 115.682],
          <double>[4.030, 115.548],
          <double>[3.517, 115.182],
          <double>[2.945, 114.873],
          <double>[2.304, 114.352],
          <double>[1.451, 113.168],
          <double>[1.267, 112.520],
          <double>[1.010, 111.928],
          <double>[0.903, 111.307],
          <double>[0.735, 110.734],
          <double>[0.832, 110.080],
          <double>[1.475, 109.526],
        ]),
        MalaysiaOutlineDataModel('Labuan', <List<double>>[
          <double>[5.340, 115.055],
          <double>[5.433, 115.093],
          <double>[5.464, 115.188],
          <double>[5.415, 115.354],
          <double>[5.335, 115.385],
          <double>[5.165, 115.355],
          <double>[5.116, 115.194],
          <double>[5.144, 115.102],
        ]),
        MalaysiaOutlineDataModel('Langkawi', <List<double>>[
          <double>[6.520, 99.580],
          <double>[6.520, 99.980],
          <double>[6.130, 99.980],
          <double>[6.130, 99.580],
        ]),
        MalaysiaOutlineDataModel('Tioman', <List<double>>[
          <double>[2.950, 104.020],
          <double>[2.950, 104.300],
          <double>[2.620, 104.300],
          <double>[2.620, 104.020],
        ]),
        MalaysiaOutlineDataModel('Redang and Perhentian', <List<double>>[
          <double>[6.000, 102.620],
          <double>[6.000, 103.120],
          <double>[5.680, 103.120],
          <double>[5.680, 102.620],
        ]),
      ];

  /// The islands **no** boundary dataset contains - not the hand-drawn
  /// coastline, and not the real geoBoundaries rings either.
  ///
  /// Kept apart from [maskCatalogue] because they are needed twice: appended to
  /// the real outline that `map_country_rings` serves, and again to the
  /// hand-drawn fallback when that outline cannot be fetched. Without them a
  /// diver at Sipadan gets cream instead of a map, and is told they are not in
  /// Malaysia.
  static const List<MalaysiaOutlineDataModel> outlyingIslands =
      <MalaysiaOutlineDataModel>[
        // Sipadan, Mabul and Ligitan, off Semporna - 27 km outside the real
        // ADM1 ring. The box stops well east of Sebatik, the nearest
        // Indonesian land.
        MalaysiaOutlineDataModel('Semporna islands', <List<double>>[
          <double>[4.350, 118.500],
          <double>[4.350, 118.750],
          <double>[4.050, 118.750],
          <double>[4.050, 118.500],
        ]),
        // Pulau Payar, the marine park south of Langkawi - 17 km outside.
        // Sits below Langkawi's box and well south of Thai waters.
        MalaysiaOutlineDataModel('Payar', <List<double>>[
          <double>[6.150, 99.850],
          <double>[6.150, 100.020],
          <double>[5.980, 100.020],
          <double>[5.980, 99.850],
        ]),
      ];
}
