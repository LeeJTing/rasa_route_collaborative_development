import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// One selectable option in the profile edit screens - a square photo box with
/// a label underneath, exactly like the mock-up's preference/restriction
/// options. Tapping it toggles selection.
///
/// Selection is drawn on the BOX, not the artwork: the photo is full colour and
/// cannot be tinted the way the old SVG icons were, so a green border plus a
/// soft green halo carry the state instead. The border is a foreground frame
/// over the photo, and the photo is inset by a thin neutral rim so that frame
/// stays visible at rest instead of dissolving into photo pixels.
///
/// Used by `EditFoodPreferenceView`, `EditDietaryRestrictionView` and
/// `ProfileSetUpView`, so it lives in `common_widgets/` rather than a view's
/// private `widgets/` folder.
///
/// [iconAsset] (from `PreferenceIcons`) shows the per-option photo; when null
/// the [icon] Material glyph is used as a generic placeholder.
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

  /// Bundled photo for this option (see `PreferenceIcons`), drawn full colour
  /// inside the box, inset by a thin neutral rim (see
  /// [AppSizes.profileOptionPhotoInset]) so the frame has its own background
  /// to read against. Null renders [icon] instead.
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
              // Box-level clip: nothing inside may paint past the rounded
              // outline (the photo gets its own concentric rounding below).
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.tagNeutralBackground,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                // The old SVG icons turned green when picked. A photo cannot, so
                // the halo under the box carries that cue instead.
                boxShadow: isSelected
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: AppColors.profileOptionSelectedGlow,
                          blurRadius: AppSizes.profileOptionSelectedGlowBlur,
                          offset: Offset(
                            0,
                            AppSizes.profileOptionSelectedGlowOffsetY,
                          ),
                        ),
                      ]
                    : null,
              ),
              // The frame is painted over the photo, not under it: under it the
              // photo hides the ring entirely and only its anti-aliased rounded
              // edge leaks the colour back, which reads as a green line broken
              // at every corner. Over it, the ring hugs the rounded box cleanly.
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isSelected ? AppColors.success : AppColors.outline,
                  width: isSelected
                      ? AppSizes.borderWidthStrong
                      : AppSizes.borderWidth,
                ),
              ),
              child: Padding(
                // The box's own fill shows as a frame margin around the photo.
                // Without it the 1pt frame line lies straight on photo pixels -
                // cream on photo - and simply stops being visible.
                padding: const EdgeInsets.all(AppSizes.profileOptionPhotoInset),
                child: ClipRRect(
                  // Concentric with the box: subtracting the inset keeps the
                  // photo's arcs parallel to the frame's.
                  borderRadius: BorderRadius.circular(
                    AppRadius.lg - AppSizes.profileOptionPhotoInset,
                  ),
                  child: iconAsset != null
                      // The photo fills the inner area: inset to the old 32pt
                      // glyph size it would read as a postage stamp at 72pt.
                      ? Image.asset(iconAsset!, fit: BoxFit.cover)
                      : Center(
                          child: Icon(
                            icon,
                            size: AppSizes.profileOptionIcon,
                            color: isSelected
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                ),
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
