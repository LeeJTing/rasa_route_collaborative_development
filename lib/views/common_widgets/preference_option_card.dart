import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// One selectable option in the profile edit screens - a square icon box with
/// a label underneath, exactly like the mock-up's preference/restriction
/// options. Tapping it toggles selection, which is drawn with a green border
/// and a white box.
///
/// Used by `EditFoodPreferenceView`, `EditDietaryRestrictionView` and
/// `ProfileSetUpView`, so it lives in `common_widgets/` rather than a view's
/// private `widgets/` folder.
///
/// [iconAsset] (from `PreferenceIcons`) shows the per-option icon SVG, tinted
/// to the selection colour; when null the [icon] Material glyph is used as a
/// generic placeholder.
class PreferenceOptionCard extends StatelessWidget {
  const PreferenceOptionCard({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon = Icons.local_dining,
    this.iconAsset,
    this.maxLabelLines = AppLayoutRatios.profileOptionGridLabelLines,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// Material icon shown when [iconAsset] is null. Defaults to the generic
  /// food placeholder.
  final IconData icon;

  /// Bundled SVG asset for this option (see `PreferenceIcons`), tinted to the
  /// selection colour. Null renders [icon] instead.
  final String? iconAsset;

  /// How many lines the label may take before it ellipsises.
  ///
  /// Defaults to the grid's allowance
  /// ([AppLayoutRatios.profileOptionGridLabelLines]), which is what the fixed-
  /// height grid cells are sized for. A horizontal option row passes `1`
  /// instead: that row has a single-line height, so a second line would make one
  /// card taller and push the row below down.
  final int maxLabelLines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: AppSizes.profileOptionBox,
              height: AppSizes.profileOptionBox,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.surface
                    : AppColors.tagNeutralBackground,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isSelected ? AppColors.success : AppColors.transparent,
                  width: AppSizes.borderWidthStrong,
                ),
              ),
              child: iconAsset != null
                  ? SizedBox(
                      width: AppSizes.profileOptionIcon,
                      height: AppSizes.profileOptionIcon,
                      child: SvgPicture.asset(
                        iconAsset!,
                        colorFilter: ColorFilter.mode(
                          isSelected
                              ? AppColors.success
                              : AppColors.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                    )
                  : Icon(
                      icon,
                      size: AppSizes.profileOptionIcon,
                      color: isSelected
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Long names (e.g. "No Coriander/Cilantro") wrap onto two lines
            // within a compact max width. In the Wrap (Chosen on top) and the
            // horizontal Row (food preference) there is no grid cell to bound
            // the label, so bound it here or the card would stretch and the
            // two-line cap would never engage as names get longer.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppSizes.profileOptionLabelMaxWidth,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: maxLabelLines,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
