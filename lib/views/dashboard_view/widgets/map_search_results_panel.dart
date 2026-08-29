import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/exploration_search.dart';
import '../../../domain_model/local_food.dart';

/// A8 step 3 - one result list, grouped under "Location" and "Local Food".
///
/// REQ102_21 shows every match for the keyword; picking a location centres the
/// map on it (REQ102_22), picking a food redraws the heatmap around that dish
/// (REQ102_33). A8.2 replaces the list with [message] (M2).
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class MapSearchResultsPanel extends StatelessWidget {
  const MapSearchResultsPanel({
    super.key,
    required this.results,
    required this.searching,
    required this.message,
    required this.onPlaceSelected,
    required this.onFoodSelected,
  });

  final ExplorationSearchResults results;
  final bool searching;

  /// A8.2 / M2 - "No location or local food matches your input."
  final String? message;

  final ValueChanged<PlaceSuggestion> onPlaceSelected;
  final ValueChanged<LocalFood> onFoodSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxHeight: AppSizes.searchSuggestionsMaxHeight,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outline),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _body(),
    );
  }

  Widget _body() {
    if (searching) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (message != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.search_off,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message!, style: AppTextStyles.bodySmall)),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (results.places.isNotEmpty) const _GroupHeading('Location'),
        ...results.places.map(
          (PlaceSuggestion place) => _ResultTile(
            icon: switch (place.kind) {
              PlaceKind.state => Icons.map_outlined,
              PlaceKind.city => Icons.location_city_outlined,
              PlaceKind.town => Icons.holiday_village_outlined,
              PlaceKind.area => Icons.explore_outlined,
              PlaceKind.landmark => Icons.star_outline,
              PlaceKind.address => Icons.storefront_outlined,
            },
            title: place.name,
            subtitle: place.subtitle,
            onTap: () => onPlaceSelected(place),
          ),
        ),
        if (results.foods.isNotEmpty) const _GroupHeading('Local Food'),
        ...results.foods.map(
          (LocalFood food) => _ResultTile(
            icon: Icons.ramen_dining_outlined,
            title: food.name,
            subtitle: <String>[
              food.category,
              food.mealType,
            ].where((String s) => s.isNotEmpty).join(' - '),
            onTap: () => onFoodSelected(food),
          ),
        ),
      ],
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.surfaceVariant,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Text(label.toUpperCase(), style: AppTextStyles.labelSmall),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall,
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}
