import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/food_distribution.dart';
import '../../../domain_model/region.dart';
import 'heatmap_scale.dart';

/// REQ102_15 - the Local Food Distribution Heatmap: all 16 Malaysian states
/// shaded by their availability score.
///
/// **Why this is painted rather than drawn on OpenStreetMap.** Malaysia's
/// bounding box is 20.3 degrees of longitude by 6.3 of latitude - a 3:1
/// letterbox. Framed honestly on a portrait phone the whole country is a
/// 390 x 120 band with thirteen labels stacked on top of each other, which is
/// unreadable and nothing like the mock-up. The mock-up solves it the way
/// atlases have always solved it: Peninsular Malaysia at full size, Borneo
/// scaled down and brought in alongside. That is
/// [StylisedMalaysiaProjection] - a deliberate, documented distortion, used
/// for this one overview only. Zoom past the threshold and REQ102_12 hands
/// over to the real OpenStreetMap detailed view, where every coordinate is
/// true again.
///
/// Each state is filled **solid** with the one colour its availability score
/// earns. It used to carry a cellular texture under a blur; the blur eroded
/// the fill at every boundary, so states looked hollow at the edges and two
/// neighbouring scores were hard to tell apart. A flat fill is what a
/// choropleth is for - the colour *is* the reading.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class RegionHeatmapCanvas extends StatefulWidget {
  const RegionHeatmapCanvas({
    super.key,
    required this.regions,
    required this.outlines,
    required this.selectedRegionCode,
    required this.onRegionTap,
    required this.onZoomedIntoRegion,
    required this.onScaleChanged,
    required this.detailScale,
    required this.resetToken,
    this.touristLatitude,
    this.touristLongitude,
  });

  final List<RegionAvailability> regions;

  /// REQ102_1 - the coastline of each landmass. The blurred fill is clipped to
  /// these, so it cannot bleed past the coast and leave a green halo outside
  /// the boundary lines.
  final List<CountryOutline> outlines;
  final double? touristLatitude;
  final double? touristLongitude;

  final String? selectedRegionCode;

  /// A2-5 - the tourist taps a state.
  final ValueChanged<RegionAvailability> onRegionTap;

  /// REQ102_12 - pinched or pressed "+" past the predefined level. The state
  /// under the middle of the screen is the one the detailed view opens on.
  final ValueChanged<RegionAvailability> onZoomedIntoRegion;

  /// Reported so the "+" / "-" buttons can be enabled and disabled correctly.
  final ValueChanged<double> onScaleChanged;

  /// The predefined zoom level, expressed as a canvas scale factor. Crossing
  /// it hands over to the detailed map.
  final double detailScale;

  /// Bumped by the ViewModel when the dashboard returns to the heatmap, so the
  /// canvas drops back to its resting scale.
  final int resetToken;
  @override
  RegionHeatmapCanvasState createState() => RegionHeatmapCanvasState();
}

/// Public so the dashboard can drive [scaleBy] from the "+" / "-"
/// buttons through a `GlobalKey`, the way `FormState` is reached.
class RegionHeatmapCanvasState extends State<RegionHeatmapCanvas> {
  final TransformationController _controller = TransformationController();

  Size _size = Size.zero;
  double _scale = 1;

  /// The overview now transitions directly to the detailed map, so the maximum
  /// scale doesn't need to be very high.
  static const double _maximumScale = 8;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(RegionHeatmapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final double next = _controller.value.getMaxScaleOnAxis();
    if ((next - _scale).abs() < 0.001) return;
    setState(() => _scale = next);
    widget.onScaleChanged(next);
  }

  /// REQ102_12 - crossing the predefined level hands over to the detailed
  /// OpenStreetMap view.
  void _checkDetailThreshold() {
    if (_scale < widget.detailScale) return;
    final RegionAvailability? region = _regionAtViewportCentre();
    if (region != null) widget.onZoomedIntoRegion(region);
  }

  /// InteractiveViewer only ever scales and translates, so inverting its
  /// matrix is two arithmetic steps rather than a full matrix inverse.
  Offset _toCanvas(Offset viewportPoint) {
    final Matrix4 m = _controller.value;
    final double scale = m.getMaxScaleOnAxis();
    final Offset translation = Offset(
      m.getTranslation().x,
      m.getTranslation().y,
    );
    return (viewportPoint - translation) / scale;
  }

  RegionAvailability? _regionAtViewportCentre() =>
      _regionAt(_toCanvas(Offset(_size.width / 2, _size.height / 2)));

  /// **The smallest area containing the point wins, not the first one found.**
  ///
  /// This is why Kuala Lumpur could not be selected. Selangor encloses it, and
  /// Selangor comes first in the catalogue, so the first-match loop handed back
  /// Selangor for every tap inside Kuala Lumpur - and the same for Putrajaya.
  /// The area with the smaller footprint is always the more specific answer.
  RegionAvailability? _regionAt(Offset canvasPoint) {
    if (_size == Size.zero) return null;
    final StylisedMalaysiaProjection projection =
        StylisedMalaysiaProjection.fit(_size);

    RegionAvailability? containing;
    double smallestBounds = double.infinity;

    RegionAvailability? nearest;
    double nearestDistance = double.infinity;

    for (final RegionAvailability availability in widget.regions) {
      final Path path = projection.pathFor(availability.region);
      if (path.contains(canvasPoint)) {
        final Rect bounds = path.getBounds();
        final double area = bounds.width * bounds.height;
        if (area < smallestBounds) {
          smallestBounds = area;
          containing = availability;
        }
      }

      final Offset centre = projection(
        availability.region.centreLatitude,
        availability.region.centreLongitude,
      );
      final double distance = (centre - canvasPoint).distanceSquared;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = availability;
      }
    }

    if (containing != null) return containing;

    // Missed the land but landed near it - treat it as the closest area rather
    // than doing nothing, which reads as an unresponsive map. The radius is
    // generous on purpose: Kuala Lumpur, Putrajaya and Labuan are a couple of
    // pixels across at country scale, and a tap that lands a finger's width off
    // one of them means it.
    return nearestDistance < _nearestTapRadiusSquared ? nearest : null;
  }

  /// 12 logical pixels, squared - about half a fingertip.
  static const double _nearestTapRadiusSquared = 144 * 144;

  /// Scales about the middle of the viewport - what the "+" / "-" buttons do
  /// (REQ102_3, REQ102_5).
  void scaleBy(double factor) {
    final double current = _controller.value.getMaxScaleOnAxis();
    final double target = (current * factor).clamp(1.0, _maximumScale);
    if ((target - current).abs() < 0.001) return;

    if (target <= 1.0001) {
      _controller.value = Matrix4.identity();
    } else {
      final double applied = target / current;
      final double fx = _size.width / 2;
      final double fy = _size.height / 2;
      final Matrix4 next = Matrix4.identity()
        ..translateByDouble(fx, fy, 0, 1)
        ..scaleByDouble(applied, applied, 1, 1)
        ..translateByDouble(-fx, -fy, 0, 1);
      // `multiply` keeps this typed as Matrix4; `*` on vector_math returns
      // dynamic.
      next.multiply(_controller.value);
      _controller.value = next;
    }
    _checkDetailThreshold();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _size = constraints.biggest;
        return ColoredBox(
          color: AppColors.background,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 1,
            maxScale: _maximumScale,
            onInteractionEnd: (_) => _checkDetailThreshold(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails details) {
                final RegionAvailability? region = _regionAt(
                  details.localPosition,
                );
                if (region != null) widget.onRegionTap(region);
              },
              child: CustomPaint(
                size: _size,
                painter: _HeatmapPainter(
                  regions: widget.regions,
                  outlines: widget.outlines,
                  selectedRegionCode: widget.selectedRegionCode,
                  touristLatitude: widget.touristLatitude,
                  touristLongitude: widget.touristLongitude,
                  scale: _scale,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Projection
// =============================================================================

/// Peninsular Malaysia at full size, Borneo scaled down and moved in beside it.
///
/// Uniform scale *within* each landmass, so neither is stretched - only the gap
/// between them is fiction. Everything is derived from the widget size, so the
/// composition fills whatever it is given.
class StylisedMalaysiaProjection {
  const StylisedMalaysiaProjection._({
    required this.unit,
    required this.peninsulaLeft,
    required this.peninsulaTop,
    required this.borneoUnit,
    required this.borneoLeft,
    required this.borneoTop,
  });

  // Bounding boxes of the two landmasses.
  static const double peninsulaWest = 99.3;
  static const double peninsulaEast = 104.6;
  static const double peninsulaSouth = 0.85;
  static const double peninsulaNorth = 7.0;
  static const double borneoWest = 109.4;
  static const double borneoEast = 119.4;
  static const double borneoSouth = 0.8;
  static const double borneoNorth = 7.15;

  /// Anything east of this is drawn in the Borneo block.
  static const double splitLongitude = 106;

  // The three numbers below were measured off the reference mock-up rather
  // than chosen: its peninsula is drawn at ~40.8 px per degree of longitude
  // and ~48.6 per degree of latitude, its Borneo at ~18.0, and Borneo's centre
  // sits ~2.7 peninsula-degrees below the peninsula's.

  /// How much smaller Borneo is drawn. Small enough that the peninsula - where
  /// most of the food and most of the users are - gets the room.
  static const double borneoRelativeScale = 0.46;

  /// Gap between the two blocks, in peninsula degrees. Zero: Borneo's left
  /// edge begins where the peninsula's right edge ends, and it clears Johor
  /// because it sits so much lower.
  static const double gapDegrees = 0;

  /// How far below the peninsula's centre Borneo's centre sits, in stretched
  /// peninsula degrees. This diagonal nesting is what lets both landmasses be
  /// large on a portrait screen.
  static const double borneoDropDegrees = 2.6;

  /// Latitude is drawn 1.22x longitude. Web Mercator would say 1.00 at these
  /// latitudes, so this is a deliberate stretch - it fills a portrait phone
  /// and it is what the reference does (measured at 1.19). Applied to both
  /// landmasses, so they stay consistent with each other.
  static const double verticalStretch = 1.22;

  /// Increased zoom means the map fills more of the available space. Margin
  /// is removed to allow maximum growth.
  static const double marginFraction = 0;

  final double unit;
  final double peninsulaLeft;
  final double peninsulaTop;
  final double borneoUnit;
  final double borneoLeft;
  final double borneoTop;

  factory StylisedMalaysiaProjection.fit(Size size) {
    const double peninsulaWidth = peninsulaEast - peninsulaWest;
    const double peninsulaHeight =
        (peninsulaNorth - peninsulaSouth) * verticalStretch;
    const double borneoWidth = (borneoEast - borneoWest) * borneoRelativeScale;
    const double borneoHeight =
        (borneoNorth - borneoSouth) * borneoRelativeScale * verticalStretch;

    const double totalWidth = peninsulaWidth + gapDegrees + borneoWidth;
    const double borneoCentreY = peninsulaHeight / 2 + borneoDropDegrees;
    const double totalHeight =
        peninsulaHeight > borneoCentreY + borneoHeight / 2
        ? peninsulaHeight
        : borneoCentreY + borneoHeight / 2;

    final double unit = <double>[
      size.width * (1 - 2 * marginFraction) / totalWidth,
      size.height * (1 - 2 * marginFraction) / totalHeight,
    ].reduce((double a, double b) => a < b ? a : b);

    final double left = (size.width - totalWidth * unit) / 2;
    final double top = (size.height - totalHeight * unit) / 2;

    return StylisedMalaysiaProjection._(
      unit: unit,
      peninsulaLeft: left,
      peninsulaTop: top,
      borneoUnit: unit * borneoRelativeScale,
      borneoLeft: left + (peninsulaWidth + gapDegrees) * unit,
      borneoTop: top + (borneoCentreY - borneoHeight / 2) * unit,
    );
  }

  Offset call(double latitude, double longitude) {
    if (longitude < splitLongitude) {
      return Offset(
        peninsulaLeft + (longitude - peninsulaWest) * unit,
        peninsulaTop + (peninsulaNorth - latitude) * verticalStretch * unit,
      );
    }
    return Offset(
      borneoLeft + (longitude - borneoWest) * borneoUnit,
      borneoTop + (borneoNorth - latitude) * verticalStretch * borneoUnit,
    );
  }

  /// Scale in pixels per degree for whichever block [longitude] falls in -
  /// used to size the mottling blobs.
  double unitAt(double longitude) =>
      longitude < splitLongitude ? unit : borneoUnit;

  /// The outline of [region] as one fillable path.
  Path pathFor(Region region) {
    final Path path = Path();
    for (int i = 0; i < region.boundary.length; i++) {
      final GeoPoint point = region.boundary[i];
      final Offset offset = call(point.latitude, point.longitude);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    return path..close();
  }
}

// =============================================================================
// Painter
// =============================================================================

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.regions,
    required this.outlines,
    required this.selectedRegionCode,
    required this.touristLatitude,
    required this.touristLongitude,
    required this.scale,
  });

  final List<RegionAvailability> regions;
  final List<CountryOutline> outlines;
  final double? touristLatitude;
  final double? touristLongitude;

  final String? selectedRegionCode;
  final double scale;

  /// Where each state's name sits, in degrees from its centre, and whether the
  /// text hangs off to the left. The narrow west-coast states have no room for
  /// a name inside them, so - as in the mock-up - their labels sit out over the
  /// Strait of Malacca.
  static const Map<String, _LabelPlacement> _placements =
      <String, _LabelPlacement>{
        'PLS': _LabelPlacement(-0.55, 0.25, toLeft: true),
        'KDH': _LabelPlacement(-0.30, 0.05, toLeft: true),
        'PNG': _LabelPlacement(-0.55, -0.05, toLeft: true),
        'SGR': _LabelPlacement(-0.60, -0.05, toLeft: true),
        'NSN': _LabelPlacement(-0.55, -0.30, toLeft: true),
        'MLK': _LabelPlacement(-0.45, -0.30, toLeft: true),
        'JHR': _LabelPlacement(0.15, -0.55),
        'PRK': _LabelPlacement(0.10, 0),
        'KTN': _LabelPlacement(0.05, 0.20),
        'TRG': _LabelPlacement(0.55, 0.15),
        'PHG': _LabelPlacement(0.10, -0.10),
        'SBH': _LabelPlacement(-0.30, -0.35),
        'SWK': _LabelPlacement(0.30, -0.55),
      };

  /// Names shortened for the map only. "Pulau Pinang" and "Negeri Sembilan"
  /// are half the width of the states they sit next to; the full names stay in
  /// the catalogue and on every other screen.
  static const Map<String, String> _shortNames = <String, String>{
    'PNG': 'Penang',
    'NSN': 'N. Sembilan',
  };

  /// Too small to label until the tourist zooms in. The threshold is lower
  /// than it was - the composition gives every state more room now, so these
  /// three become legible sooner.
  static const Set<String> _labelOnlyWhenZoomed = <String>{'KUL', 'PJY', 'LBN'};

  static const double _smallStateLabelScale = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final StylisedMalaysiaProjection projection =
        StylisedMalaysiaProjection.fit(size);

    // --- the fills ----------------------------------------------------------
    // Clipped to the coastline so nothing can paint outside Malaysia
    // (REQ102_1), then one solid fill per area.
    final Path? coast = _coastPath(projection);
    if (coast != null) {
      canvas.save();
      canvas.clipPath(coast);
    }

    for (final RegionAvailability availability in regions) {
      canvas.drawPath(
        projection.pathFor(availability.region),
        Paint()
          ..style = PaintingStyle.fill
          ..color = heatmapColourFor(availability.score),
      );
    }

    if (coast != null) canvas.restore();

    // --- state boundaries ----------------------------------------------------
    // Adjacent states share their seam coordinates, so every internal boundary
    // is one line drawn twice over itself rather than two lines a hair apart.
    for (final RegionAvailability availability in regions) {
      final bool selected = availability.region.code == selectedRegionCode;
      // Kuala Lumpur, Putrajaya and Labuan are specks at overview scale - an
      // outline round them reads as a stray box, not a state.
      if (!selected &&
          _labelOnlyWhenZoomed.contains(availability.region.code) &&
          scale < _smallStateLabelScale) {
        continue;
      }
      canvas.drawPath(
        projection.pathFor(availability.region),
        Paint()
          ..style = PaintingStyle.stroke
          // Divided by the canvas scale so the line keeps the same width on
          // screen however far the tourist has pinched in.
          ..strokeWidth =
              (selected
                  ? AppSizes.heatmapSelectedBorderWidth
                  : AppSizes.heatmapBorderWidth) /
              scale
          ..strokeJoin = StrokeJoin.round
          ..color = selected
              ? AppColors.primary
              : AppColors.heatmapBorder.withValues(
                  alpha: AppColors.heatmapBorderOpacity,
                ),
      );
    }

    // --- labels, painted last so nothing crosses them ------------------------
    for (final RegionAvailability availability in regions) {
      _paintLabel(canvas, size, projection, availability);
    }

    _paintTourist(canvas, projection);
  }

  /// REQ102_7 - the tourist's own position. The overview is a stylised
  /// projection, so this dot is "which state you are in", not a survey fix -
  /// which is all it needs to be at country zoom.
  void _paintTourist(Canvas canvas, StylisedMalaysiaProjection projection) {
    final double? latitude = touristLatitude;
    final double? longitude = touristLongitude;
    if (latitude == null || longitude == null) return;

    final Offset centre = projection(latitude, longitude);

    // **A ring, not a disc, and it does not grow with the canvas.**
    //
    // Filled, at country scale, this marker covered Kuala Lumpur and Putrajaya
    // completely - the tourist could neither see their score nor tap them,
    // because the thing showing where they are was larger than where they were.
    // An outline leaves the fill underneath legible, and dividing by the canvas
    // scale keeps it the same size on screen however far in the tourist has
    // pinched, so it never blocks more of the map than it does at rest.
    //
    // Reduced to 8pt diameter to keep small territories clear.
    final double radius = (8 / 2) / scale;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale
        ..color = AppColors.surface,
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale
        ..color = AppColors.currentLocationMarker,
    );
    // A small solid centre, so it still reads as a position fix rather than as
    // a circle drawn on the map.
    canvas.drawCircle(
      centre,
      0.8 / scale,
      Paint()..color = AppColors.currentLocationMarker,
    );
  }

  /// One path covering every Malaysian landmass, or null before the outlines
  /// have loaded (in which case the fill simply goes unclipped).
  Path? _coastPath(StylisedMalaysiaProjection projection) {
    if (outlines.isEmpty) return null;
    final Path path = Path();
    for (final CountryOutline outline in outlines) {
      if (outline.ring.length < 3) continue;
      path.addPolygon(
        outline.ring
            .map(
              (GeoPoint point) => projection(point.latitude, point.longitude),
            )
            .toList(growable: false),
        true,
      );
    }
    return path;
  }

  void _paintLabel(
    Canvas canvas,
    Size size,
    StylisedMalaysiaProjection projection,
    RegionAvailability availability,
  ) {
    final String code = availability.region.code;
    if (_labelOnlyWhenZoomed.contains(code) && scale < _smallStateLabelScale) {
      return;
    }

    final _LabelPlacement placement =
        _placements[code] ?? const _LabelPlacement(0, 0);

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: _shortNames[code] ?? availability.region.name,
        style: AppTextStyles.mapMicroLabel.copyWith(
          // Smaller than the label scale's 11: thirteen state names have to
          // share a 155pt-wide peninsula.
          color: AppColors.heatmapLabel,
          fontWeight: FontWeight.w700,
          shadows: const <Shadow>[
            Shadow(color: AppColors.background, blurRadius: 3),
            Shadow(color: AppColors.background, blurRadius: 6),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final Offset anchor = projection(
      availability.region.centreLatitude + placement.latitudeOffset,
      availability.region.centreLongitude + placement.longitudeOffset,
    );

    final double dx = placement.toLeft
        ? anchor.dx - painter.width - 3
        : anchor.dx - painter.width / 2;

    painter.paint(
      canvas,
      Offset(
        dx.clamp(2.0, size.width - painter.width - 2),
        anchor.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) =>
      oldDelegate.regions != regions ||
      oldDelegate.outlines != outlines ||
      oldDelegate.touristLatitude != touristLatitude ||
      oldDelegate.touristLongitude != touristLongitude ||
      oldDelegate.selectedRegionCode != selectedRegionCode ||
      oldDelegate.scale != scale;
}

/// Where one state's name sits relative to its centre, in degrees.
class _LabelPlacement {
  const _LabelPlacement(
    this.longitudeOffset,
    this.latitudeOffset, {
    this.toLeft = false,
  });

  final double longitudeOffset;
  final double latitudeOffset;

  /// The label hangs off to the left of the anchor instead of being centred.
  final bool toLeft;
}
