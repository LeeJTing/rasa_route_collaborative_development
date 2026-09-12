import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// The search field floating over the dashboard map (A8, REQ102_18 -
/// REQ102_21, REQ102_30).
///
/// Two variants, both from the Figma frames: the *Heatmap View* pairs a 264
/// wide field with a 92 wide "Filter" pill, and the *Detialed Map View* gives
/// the field the full 347 because the filter panel only applies to the
/// country-wide heatmap.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class MapSearchBar extends StatelessWidget {
  const MapSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onTap,
    this.onSubmitted,
    this.onFilterTap,
    this.filterCount = 0,
    this.filterPanelOpen = false,
    this.hintText = 'Search a state, city or local food',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// A8.3 - clears the keyword and restores the map.
  final VoidCallback onClear;

  final VoidCallback onTap;

  /// The keyboard's Search key.
  ///
  /// The field already asked for that key with [TextInputAction.search] but
  /// had nothing wired to it, so pressing it did nothing at all: the only way
  /// to get results was to type another character and wait out the debounce.
  final ValueChanged<String>? onSubmitted;

  /// Null hides the Filter pill - the detailed-map variant.
  final VoidCallback? onFilterTap;

  /// Number of ticked options across all four groups, shown as a badge.
  final int filterCount;

  final bool filterPanelOpen;

  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _field()),
        if (onFilterTap != null) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          _filterButton(),
        ],
      ],
    );
  }

  Widget _field() {
    return Container(
      height: AppSizes.searchFieldHeight,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.outline),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.search,
            size: AppSizes.mapControlIconSize,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onTap: onTap,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium,
              inputFormatters: [
                LengthLimitingTextInputFormatter(30), // Sets the limit to 10 characters
              ],
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textDisabled,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            InkWell(
              onTap: onClear,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterButton() {
    return Material(
      color: filterPanelOpen ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 1,
      shadowColor: AppColors.shadow,
      child: InkWell(
        onTap: onFilterTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: AppSizes.mapFilterButtonWidth,
          height: AppSizes.mapSearchFieldHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.tune,
                size: 16,
                color: filterPanelOpen
                    ? AppColors.onPrimary
                    : AppColors.textPrimary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                filterCount == 0 ? 'Filter' : 'Filter ($filterCount)',
                style: AppTextStyles.compactControlLabel.copyWith(
                  color: filterPanelOpen
                      ? AppColors.onPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
