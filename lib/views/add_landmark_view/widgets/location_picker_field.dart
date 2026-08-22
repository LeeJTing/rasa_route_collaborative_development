import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/config/env.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../model/data_models/location_data_model.dart';

/// Reusable piece of `AddLandmarkView`: an OpenStreetMap showing the GPS fix
/// with a draggable pin (A9).
///
/// The pin starts on the fix and can be tapped to a new spot, but only within
/// 100m of it - [onMove] hands the tapped coordinate up to the ViewModel,
/// which enforces the range and rejects an out-of-range move (A9.1, M9, shown
/// via [errorMessage]); the pin then stays at its last valid position.
///
/// Tiles come from `Env.osmTileUrl` (OpenStreetMap - no API key needed). The
/// map only renders once both [center] and [pin] are known; until the first
/// GPS fix arrives it shows "Locating...".
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
  });

  /// The GPS fix - map centre and the anchor for the 100m radius.
  final LocationDataModel center;

  /// Where the pin currently sits (the fix, or the last accepted adjustment).
  final LocationDataModel pin;

  /// Called with a tapped lat/lng so the ViewModel can validate the 100m rule.
  final void Function(double latitude, double longitude) onMove;

  /// Rejected out-of-range move (A9.1, M9).
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final bool known = center.isKnown && pin.isKnown;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Location (GPS)', style: AppTextStyles.titleSmall),
            const SizedBox(height: AppSpacing.sm),
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
                      // The 100m allowance, drawn around the GPS fix.
                      CircleLayer(
                        circles: <CircleMarker>[
                          CircleMarker(
                            point: LatLng(center.latitude, center.longitude),
                            radius: 100,
                            useRadiusInMeter: true,
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderColor: AppColors.primary,
                            borderStrokeWidth: 1,
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
              Text(
                '${pin.latitude.toStringAsFixed(5)}, '
                '${pin.longitude.toStringAsFixed(5)}',
                style: AppTextStyles.bodySmall,
              ),
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
