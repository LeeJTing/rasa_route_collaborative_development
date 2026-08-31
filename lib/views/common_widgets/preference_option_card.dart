import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// One selectable option in the profile edit screens - a square icon box with
/// a label underneath, exactly like the mock-up's preference/restriction
/// options. Tapping it toggles selection, which is drawn with a green border
/// and a white box.
///
/// Used by `EditFoodPreferenceView` and `EditDietaryRestrictionView`, so it
/// lives in `common_widgets/` rather than a view's private `widgets/` folder.
///
/// NOTE: the option images are not added yet - the box shows a placeholder
/// icon until the real images (one per option) exist. Swap the icon for the
/// image once available.
class PreferenceOptionCard extends StatelessWidget {
  const PreferenceOptionCard({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.maxLabelLines = 2,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// How many lines the label may take before it is ellipsised. The dietary
  /// "Chosen on top" Wrap passes 1 so a long restriction name truncates to a
  /// single line and keeps every card the same height (a second line made one
  /// card taller and pushed the row below down). The "All Restrictions" grid
  /// keeps 2 so names can wrap within its fixed-height cell.
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
              child: Icon(
                Icons.local_dining,
                size: AppSizes.profileOptionIcon,
                color: isSelected ? AppColors.success : AppColors.textSecondary,
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
