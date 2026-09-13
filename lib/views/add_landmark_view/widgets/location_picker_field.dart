import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/config/env.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/tourist_location.dart';

/// Reusable piece of `AddLandmarkView`: an OpenStreetMap showing the captured
/// GPS fix with a draggable pin (A9).
///
/// [center] is the FIRST food's capture spot - the landmark's anchor. The pin
/// starts on it and can be tapped to a new spot, but only within 100 m of it
/// (A9.1) - [onMove] hands the tapped coordinate up to the ViewModel, which
/// enforces the range and rejects an out-of-range move (A9.1, M9, shown via
/// [errorMessage]); the pin then stays at its last valid position.
///
/// Once the pin has been moved, [onRecover] renders a "Recover to captured
/// location" button that puts it back on the capture spot - the View passes
/// null while the pin is still there. The capture spot is also drawn as a
/// small dot so the animation's destination is never a mystery.
///
/// Tiles come from `Env.osmTileUrl` (OpenStreetMap - no API key needed). The
/// map only renders once both [center] and [pin] are known; until the first
/// GPS fix arrives it shows "Locating...". The OpenStreetMap attribution is
/// required by the tile licence.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class LocationPickerField extends StatelessWidget {
  const LocationPickerField({
    super.key,
    required this.center,
    required this.pin,
    required this.onMove,
    this.errorMessage,
    this.onRecover,
    this.rangeMetres = 100,
  });

  /// The first food's capture spot - map centre and the anchor for the 100 m
  /// radius.
  final TouristLocation center;

  /// Where the pin currently sits (the capture spot, or the last accepted
  /// adjustment).
  final TouristLocation pin;

  /// Called with a tapped lat/lng so the ViewModel can validate the 100 m rule.
  final void Function(double latitude, double longitude) onMove;

  /// Rejected out-of-range move (A9.1, M9).
  final String? errorMessage;

  /// Puts the pin back on [center] - rendered only when the pin is away from
  /// it (null otherwise).
  final VoidCallback? onRecover;

  /// The pin's correction allowance (A9.1), in metres - the radius drawn
  /// around the fix. Comes from the ViewModel so the circle and the enforced
  /// rule can never disagree; the default matches the rule's own default.
  final double rangeMetres;

  @override
  Widget build(BuildContext context) {
    final bool known = center.isKnown && pin.isKnown;
    final bool moved =
        known &&
        (pin.latitude != center.latitude || pin.longitude != center.longitude);

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!known)
              const Text('Locating...', style: AppTextStyles.bodyMedium)
            else ...<Widget>[
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: AppRadius.cardRadius,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(center.latitude, center.longitude),
                      initialZoom: 16,
                      onTap: (TapPosition _, LatLng point) =>
                          onMove(point.latitude, point.longitude),
                    ),
                    children: <Widget>[
                      TileLayer(
                        urlTemplate: Env.osmTileUrl,
                        userAgentPackageName: 'com.rasaroute.app',
                      ),
                      // The pin allowance, drawn around the captured spot.
                      CircleLayer(
                        circles: <CircleMarker>[
                          CircleMarker(
                            point: LatLng(center.latitude, center.longitude),
                            radius: rangeMetres,
                            useRadiusInMeter: true,
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderColor: AppColors.primary,
                            borderStrokeWidth: 1,
                          ),
                        ],
                      ),
                      // The captured spot itself, so "recover" has a visible
                      // destination once the pin has been moved away.
                      if (moved)
                        CircleLayer(
                          circles: <CircleMarker>[
                            CircleMarker(
                              point: LatLng(center.latitude, center.longitude),
                              radius: 6,
                              useRadiusInMeter: false,
                              color: AppColors.textSecondary,
                              borderColor: Colors.white,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: <Marker>[
                          Marker(
                            point: LatLng(pin.latitude, pin.longitude),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_pin,
                              size: 40,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${pin.latitude.toStringAsFixed(5)}, '
                      '${pin.longitude.toStringAsFixed(5)}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                  Text(
                    '© OpenStreetMap contributors',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (onRecover != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRecover,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Recover to captured location'),
                  ),
                ),
              ],
            ],
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                errorMessage!,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
