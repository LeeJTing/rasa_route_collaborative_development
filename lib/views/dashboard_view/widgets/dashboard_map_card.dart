import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// The floating white card the dashboard map slides up from the bottom.
///
/// One shell, two users: the state summary the heatmap shows when a state is
/// tapped, and the brief restaurant overlay of A11. Both are a title, a
/// subtitle, a few facts and one primary action, so they share this rather
/// than each rolling their own.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class DashboardMapCard extends StatelessWidget {
  const DashboardMapCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onDismiss,
    this.leading,
    this.facts = const <String>[],
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;

  /// A11.1 - tapping the map outside the card, or the close button here.
  final VoidCallback onDismiss;

  final Widget? leading;

  /// Short one-line facts listed under the subtitle.
  final List<String> facts;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return PullToDismissSheet(
      onDismiss: onDismiss,
      child: Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.sheetRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, -2)),
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
          Semantics(
            label: 'Pull down to close',
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTextStyles.titleMedium),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            for (final String fact in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      Icons.circle,
                      size: 5,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(fact, style: AppTextStyles.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Wraps a bottom sheet so it can be pulled down to dismiss.
///
/// Replaces the close button the sheets used to carry. A grabber you can drag
/// is the gesture people already expect from a bottom sheet, and it puts the
/// dismiss target where the thumb already is instead of in the far corner.
///
/// The sheet follows the finger while dragging and springs back if released
/// short of the threshold, so a half-hearted pull reads as "not yet" rather
/// than doing nothing. Only downward travel counts - dragging up must not lift
/// the sheet off the bottom of the screen.
class PullToDismissSheet extends StatefulWidget {
  const PullToDismissSheet({
    super.key,
    required this.child,
    required this.onDismiss,
  });

  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<PullToDismissSheet> createState() => _PullToDismissSheetState();
}

class _PullToDismissSheetState extends State<PullToDismissSheet> {
  double _offset = 0;
  bool _dragging = false;

  /// Far enough to be deliberate, short enough not to be a workout.
  static const double _dismissDistance = 90;

  /// A flick closes it even if it never travelled the full distance.
  static const double _dismissVelocity = 700;

  void _settle() => setState(() {
    _dragging = false;
    _offset = 0;
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => setState(() => _dragging = true),
      onVerticalDragUpdate: (DragUpdateDetails details) => setState(() {
        _offset = (_offset + details.delta.dy).clamp(0.0, 400.0);
      }),
      onVerticalDragEnd: (DragEndDetails details) {
        final bool dismiss =
            _offset > _dismissDistance ||
            (details.primaryVelocity ?? 0) > _dismissVelocity;
        _settle();
        if (dismiss) widget.onDismiss();
      },
      onVerticalDragCancel: _settle,
      child: TweenAnimationBuilder<double>(
        // Zero duration while the finger is down so the sheet tracks it
        // exactly; the duration only exists for the spring back.
        tween: Tween<double>(begin: 0, end: _offset),
        duration: _dragging
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (BuildContext context, double value, Widget? child) =>
            Transform.translate(offset: Offset(0, value), child: child),
        child: widget.child,
      ),
    );
  }
}
