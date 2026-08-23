import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// REQ102_10 - the Swipe Mode panel, shown as soon as the detailed map view is
/// active.
///
/// REQ103_1 describes it as "a sliding bottom-sheet", so it has two states.
/// **Collapsed is the resting state**: a 66pt peek carrying the grabber, what
/// the map is currently filtered to, and the Matches count. Expanded it grows
/// to the 236pt frame from the Figma "Detialed Map View" - a 167 x 218 Target
/// Frame centred over the bottom of the map with a queue card either side.
///
/// It starts collapsed deliberately. Expanded, the bar covers 40% of the map
/// on a 390 x 844 phone, and until REQ103 fills it there is nothing inside
/// worth that much of the screen.
///
/// **Scope.** REQ102 requires the panel to *appear*; the localised food queue,
/// the horizontal swipe into the Target Frame, the tap gestures, the Matches
/// list and the state-scoped session are all REQ103. This widget is the frame
/// REQ103 fills in: give the card slots real content, and wire [onMatchesTap]
/// to the Matches page.
///
/// **Wiring the map to the Target Frame (REQ103_8).** When a card settles in
/// the frame, call `DashboardViewModel.showFoodInTargetFrame(food)`. That one
/// call rescores the heatmap and re-pins the detailed map for that dish; pass
/// null when the deck empties or Swipe Mode closes. Nothing else needs
/// touching - do not reach for `mapPins` or `foodDistribution` from here.
///
/// The path the food takes:
///
/// ```text
/// card in Target Frame
///   -> DashboardViewModel.showFoodInTargetFrame(food)   @param food (swipe mode)
///        -> _selectedFood
///        -> DiscoveryLogicFacade.mapPins(localFoodId: food.id)         [pins]
///        -> DiscoveryLogicFacade.foodDistribution(localFoodId: food.id) [heatmap]
/// ```
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class DiscoveryLayerBar extends StatelessWidget {
  const DiscoveryLayerBar({
    super.key,
    required this.contextLabel,
    required this.matchesCount,
    required this.onMatchesTap,
    required this.expanded,
    required this.onToggle,
  });

  /// What the map is currently narrowed to - "All local food", a dish name, or
  /// the active filter count.
  final String contextLabel;

  /// REQ103_14 - increments as the tourist likes food cards. Zero until the
  /// swipe deck is implemented.
  final int matchesCount;

  final VoidCallback onMatchesTap;

  final bool expanded;

  /// Tapping the header, or dragging it up and down.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: expanded
          ? AppSizes.discoveryLayerBarHeight
          : AppSizes.discoveryLayerBarCollapsedHeight,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.sheetRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 14,
            offset: Offset(0, -2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Header(
            contextLabel: contextLabel,
            matchesCount: matchesCount,
            expanded: expanded,
            onToggle: onToggle,
            onMatchesTap: onMatchesTap,
          ),
          if (expanded)
            const Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _QueueCardSlot(),
                  SizedBox(width: AppSpacing.sm),
                  _TargetFrameSlot(),
                  SizedBox(width: AppSpacing.sm),
                  _QueueCardSlot(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The grabber row. Doubles as the drag handle and the tap target.
class _Header extends StatelessWidget {
  const _Header({
    required this.contextLabel,
    required this.matchesCount,
    required this.expanded,
    required this.onToggle,
    required this.onMatchesTap,
  });

  final String contextLabel;
  final int matchesCount;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onMatchesTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      // Drag the sheet the way the gesture suggests: up opens, down closes.
      onVerticalDragEnd: (DragEndDetails details) {
        final double velocity = details.primaryVelocity ?? 0;
        if (velocity < -80 && !expanded) onToggle();
        if (velocity > 80 && expanded) onToggle();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.swipe_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    expanded ? 'Swipe Mode' : contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _MatchesPill(count: matchesCount, onTap: onMatchesTap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// REQ103_3 - the active zone in the centre of the Layer Bar. Outlined in the
/// brand colour so it reads as the target even while empty.
class _TargetFrameSlot extends StatelessWidget {
  const _TargetFrameSlot();

  @override
  Widget build(BuildContext context) => Container(
    width: AppSizes.discoveryTargetCardWidth,
    height: AppSizes.discoveryTargetCardHeight * 0.7,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      border: Border.all(color: AppColors.primary, width: 2),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
      ],
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.swipe_outlined, size: 26, color: AppColors.primary),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Target Frame',
          style: AppTextStyles.titleSmall.copyWith(
            color: AppColors.primary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Swipe Mode arrives with the Food Discovery module (REQ103).',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
        ),
      ],
    ),
  );
}

/// The cards queued either side of the Target Frame.
class _QueueCardSlot extends StatelessWidget {
  const _QueueCardSlot();

  @override
  Widget build(BuildContext context) => Container(
    width: AppSizes.discoveryQueueCardWidth * 0.45,
    height: AppSizes.discoveryQueueCardHeight * 0.62,
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.8),
      borderRadius: AppRadius.cardRadius,
      border: Border.all(color: AppColors.outline),
    ),
    child: const Center(
      child: Icon(
        Icons.restaurant_menu,
        size: 18,
        color: AppColors.textDisabled,
      ),
    ),
  );
}

/// REQ103_14 - the floating Matches badge.
class _MatchesPill extends StatelessWidget {
  const _MatchesPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.secondary,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    elevation: 1,
    shadowColor: AppColors.shadow,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.favorite, size: 12, color: AppColors.textPrimary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Matches $count',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
