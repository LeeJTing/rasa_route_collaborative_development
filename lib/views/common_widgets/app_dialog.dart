import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Diameter of the round icon badge at the top of an [AppDialog].
const double _badgeDiameter = 64;

/// Icon inside [_badgeDiameter].
const double _badgeIconSize = 32;

/// Rasa Route's standard modal frame: a rounded card holding a centred icon
/// badge and heading, a centred message, an optional [extra] block, then a
/// stacked, full-width action column (primary action first, quieter choices
/// underneath).
///
/// Every dialog in the Add-Landmark / recognition flow uses this frame - the
/// "Before you start" reminder and the "Leave this form?" confirmation - so
/// they share one gutter and one alignment. A plain `AlertDialog` does not
/// work here: the app's button theme is full-width (`Size.fromHeight`), so
/// its right-aligned action row scattered the buttons across the card
/// instead of aligning them.
///
/// The card scrolls instead of overflowing on short screens or with large
/// accessibility text.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.extra,
    required this.actions,
  });

  /// Icon in the circular badge - the dialog's visual anchor.
  final IconData icon;

  /// Centred heading, e.g. "Leave this form?".
  final String title;

  /// Centred body line under the heading.
  final String? message;

  /// Optional block between the message and the actions - see [AppDialogRule].
  final Widget? extra;

  /// Actions stacked full width, in order - put the primary action first
  /// and any destructive choice last.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: _badgeDiameter,
                height: _badgeDiameter,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: _badgeIconSize,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (extra != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              extra!,
            ],
            const SizedBox(height: AppSpacing.xl),
            for (int index = 0; index < actions.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: AppSpacing.xs),
              actions[index],
            ],
          ],
        ),
      ),
    );
  }
}

/// One rule row for an [AppDialog]'s [AppDialog.extra] block: a leading icon
/// and its text sharing one start edge, wrapped in a soft card so stacked
/// rows line up as a column (the Add-New-Landmark reminder and the
/// unfinished-submission notice both explain themselves with these).
class AppDialogRule extends StatelessWidget {
  const AppDialogRule({super.key, required this.icon, required this.text});

  /// Leading icon, drawn in the primary colour at [AppSizes.iconSmall].
  final IconData icon;

  /// The rule's text - a single sentence, wrapped as needed.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.insetSurface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppSizes.iconSmall, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
