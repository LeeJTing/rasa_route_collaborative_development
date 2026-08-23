import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/food_distribution.dart';
import '../../../domain_model/map.dart';
import '../../common_widgets/app_image.dart';
import 'dashboard_map_card.dart';
import 'heatmap_scale.dart';

/// A2-5 / A2-6 - the tourist taps a state on the heatmap, sees what it holds,
/// and opens it.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class RegionScoreCard extends StatelessWidget {
  const RegionScoreCard({
    super.key,
    required this.availability,
    required this.onDismiss,
    required this.onExplore,
  });

  final RegionAvailability availability;
  final VoidCallback onDismiss;

  /// REQ102_22 - centre and zoom the map on this state, which crosses the
  /// predefined zoom level and opens the detailed map view (REQ102_12).
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final int percent = (availability.score * 100).round();
    return DashboardMapCard(
      title: availability.region.name,
      subtitle: availability.maximumFoodCount == 0
          ? 'No local food mapped in Malaysia yet'
          : 'Availability score $percent% of the best-served state',
      onDismiss: onDismiss,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: heatmapColourFor(availability.score),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: Text(
          '${availability.availableFoodCount}',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.onPrimary,
          ),
        ),
      ),
      facts: <String>[
        '${availability.availableFoodCount} distinct local food'
            '${availability.availableFoodCount == 1 ? '' : 's'} available here',
        '${availability.occurrenceCount} restaurant'
            '${availability.occurrenceCount == 1 ? '' : 's'} and submitted '
            'landmark${availability.occurrenceCount == 1 ? '' : 's'} serving them',
      ],
      actionLabel: 'Explore ${availability.region.name}',
      onAction: onExplore,
    );
  }
}

/// A11 - the sheet that appears when a pin on the detailed map view is tapped.
///
/// Laid out from the Figma "Click Map Pin" frame: a 102 square photo on the
/// left, and beside it the name, a distance and rating row, the cuisine line,
/// and "RM20-40 | Open now". Under that the "Serves: ..." strip, then the
/// "View Restaurant" button.
///
/// Every field degrades on its own. No photo falls back to the shared
/// placeholder; no fix yet and the distance is simply absent; **no opening
/// hours on record reads "Hours unknown", never "Closed"** - the app does not
/// tell a tourist a place is shut when it does not know.
///
/// C12 lists everything the Restaurant Details page shows; this is the short
/// version, and the button opens the full page (A11-4).
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class RestaurantPinSheet extends StatelessWidget {
  const RestaurantPinSheet({
    super.key,
    required this.pin,
    required this.onDismiss,
    required this.onOpen,
  });

  final MapPin pin;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  bool get _isLandmark => pin.kind == MapPinKind.landmark;

  @override
  Widget build(BuildContext context) {
    return PullToDismissSheet(
      onDismiss: onDismiss,
      child: Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.sheetRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Grabber(),
          const SizedBox(height: AppSpacing.md),
          _Header(pin: pin, isLandmark: _isLandmark),
          const SizedBox(height: AppSpacing.md),
          _ServesStrip(foods: pin.servedFoods),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: FilledButton(
              onPressed: onOpen,
              child: Text(
                _isLandmark ? 'View Landmark' : 'View Restaurant',
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The pull handle. No close button - the sheet is dismissed by dragging it
/// down, which is what the handle is advertising.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Pull down to close',
    child: Center(
      child: Container(
        width: 67,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.outline,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.pin, required this.isLandmark});

  final MapPin pin;
  final bool isLandmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: AppSizes.pinSheetImage,
          height: AppSizes.pinSheetImage,
          child: AppImage(
            source: pin.imageUrl,
            borderRadius: AppRadius.cardRadius,
            semanticLabel: pin.label,
            fallback: ColoredBox(
              color: AppColors.surfaceVariant,
              child: Center(
                child: Icon(
                  Icons.location_on,
                  size: 32,
                  color: isLandmark
                      ? AppColors.pinUserLandmark
                      : AppColors.pinSystemRestaurant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                pin.label.isEmpty ? 'Unnamed place' : pin.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              _MetaRow(pin: pin),
              const SizedBox(height: AppSpacing.xs),
              Text(
                pin.category?.isNotEmpty == true
                    ? pin.category!
                    : (isLandmark
                          ? 'Landmark submitted by a tourist'
                          : 'Restaurant from the system catalogue'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              _PriceAndStatus(pin: pin),
            ],
          ),
        ),
      ],
    );
  }
}

/// Distance and rating - the icon-plus-two-values row in the Figma frame.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.pin});

  final MapPin pin;

  @override
  Widget build(BuildContext context) {
    final double? metres = pin.distanceMetres;
    final double? rating = pin.rating;
    if (metres == null && rating == null) return const SizedBox.shrink();

    return Row(
      children: <Widget>[
        if (metres != null) ...<Widget>[
          const Icon(
            Icons.near_me_outlined,
            size: 12,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(_distanceLabel(metres), style: AppTextStyles.bodySmall),
        ],
        if (metres != null && rating != null)
          const SizedBox(width: AppSpacing.sm),
        if (rating != null) ...<Widget>[
          const Icon(Icons.star, size: 12, color: AppColors.secondary),
          const SizedBox(width: 4),
          Text(rating.toStringAsFixed(1), style: AppTextStyles.bodySmall),
        ],
      ],
    );
  }

  /// Straight-line distance, said plainly. Metres under a kilometre, one
  /// decimal above.
  static String _distanceLabel(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';
}

class _PriceAndStatus extends StatelessWidget {
  const _PriceAndStatus({required this.pin});

  final MapPin pin;

  @override
  Widget build(BuildContext context) {
    final bool? openNow = pin.openNow;
    final String status = openNow == null
        ? 'Hours unknown'
        : openNow
        ? 'Open now'
        : 'Closed now';
    final Color statusColour = openNow == null
        ? AppColors.textSecondary
        : openNow
        ? AppColors.success
        : AppColors.error;

    return Row(
      children: <Widget>[
        if (pin.priceRange != null) ...<Widget>[
          Text(
            pin.priceRange!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.accentRust,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text('  |  ', style: AppTextStyles.bodySmall),
        ],
        Flexible(
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: statusColour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Serves: Nasi Lemak, Teh Tarik" - the matching dishes on the menu here.
class _ServesStrip extends StatelessWidget {
  const _ServesStrip({required this.foods});

  final List<String> foods;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: AppSizes.pinSheetServesStrip),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.insetSurface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Text(
        foods.isEmpty
            ? 'No matching local food listed here yet'
            : 'Serves: ${foods.join(', ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}
