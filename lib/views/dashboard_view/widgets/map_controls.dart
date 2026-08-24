import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// The stacked "+" / "-" control on the right of the map (REQ102_3,
/// REQ102_5).
///
/// 44 x 73 with a hairline between the halves - the Figma "Zoom in/out" frame,
/// which appears at the same size on both the Heatmap View and the Detialed
/// Map View.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class MapZoomControl extends StatelessWidget {
  const MapZoomControl({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.canZoomIn = true,
    this.canZoomOut = true,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool canZoomIn;
  final bool canZoomOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.mapControlBackground,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      elevation: 2,
      shadowColor: AppColors.shadow,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: AppSizes.mapControlWidth,
        height: AppSizes.mapZoomControlHeight,
        child: Column(
          children: <Widget>[
            Expanded(
              child: _ControlButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                enabled: canZoomIn,
                onTap: onZoomIn,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Divider(
                height: 1,
                thickness: 1,
                color: AppColors.mapControlDivider,
              ),
            ),
            Expanded(
              child: _ControlButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                enabled: canZoomOut,
                onTap: onZoomOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// REQ102_9 / A14 - shown only once a GPS fix inside Malaysia is available.
///
/// The Figma "Find me button" frame: 44 x 38, a rounded rectangle matching the
/// zoom control above it rather than a circle, with the 20px send/navigate
/// glyph the mock-up names "Find me".
class MapFindMeButton extends StatelessWidget {
  const MapFindMeButton({super.key, required this.onTap, this.busy = false});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.mapControlBackground,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      elevation: 2,
      shadowColor: AppColors.shadow,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: AppSizes.mapControlWidth,
        height: AppSizes.mapFindMeHeight,
        child: busy
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _ControlButton(
                icon: Icons.near_me,
                tooltip: 'Find me',
                enabled: true,
                onTap: onTap,
              ),
      ),
    );
  }
}

/// REQ102_11 / A9 - the round Quick Mode button in the bottom-left of the
/// detailed map view.
class MapQuickModeButton extends StatelessWidget {
  const MapQuickModeButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Quick Mode',
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: AppColors.shadow,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: AppSizes.mapQuickModeButton,
            height: AppSizes.mapQuickModeButton,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.bolt, size: 22, color: AppColors.onPrimary),
                Text(
                  'Quick',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.onPrimary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: enabled ? onTap : null,
      child: Center(
        child: Icon(
          icon,
          size: AppSizes.mapControlIconSize,
          color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
        ),
      ),
    ),
  );
}
