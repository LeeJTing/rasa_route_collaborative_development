import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/local_food.dart';

/// REQ103's constructor-driven Discovery Layer Bar.
///
/// Horizontal movement changes the card in the Target Frame; double tap likes
/// it. The ViewModel owns the queue/session and tells the dashboard map which
/// food is active, while this widget owns gesture recognition and animation.
class DiscoveryLayerBar extends StatelessWidget {
  const DiscoveryLayerBar({
    super.key,
    required this.contextLabel,
    required this.matchesCount,
    required this.onMatchesTap,
    required this.expanded,
    required this.onToggle,
    required this.currentFood,
    required this.previousFood,
    required this.nextFood,
    required this.currentFoodRestricted,
    required this.currentFoodLiked,
    required this.loading,
    required this.errorMessage,
    required this.showResumePrompt,
    required this.stateName,
    required this.savedCardCount,
    required this.savedLikeCount,
    required this.savedRestaurantCount,
    required this.likeRevision,
    required this.onPrevious,
    required this.onNext,
    required this.onFoodTap,
    required this.onLike,
    required this.onHeartTap,
    required this.onContinue,
    required this.onStartNew,
  });

  final String contextLabel;
  final int matchesCount;
  final VoidCallback onMatchesTap;
  final bool expanded;
  final VoidCallback onToggle;
  final LocalFood? currentFood;
  final LocalFood? previousFood;
  final LocalFood? nextFood;
  final bool currentFoodRestricted;
  final bool currentFoodLiked;
  final bool loading;
  final String? errorMessage;
  final bool showResumePrompt;
  final String stateName;
  final int savedCardCount;
  final int savedLikeCount;
  final int savedRestaurantCount;
  final int likeRevision;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<LocalFood> onFoodTap;
  final VoidCallback onLike;
  final VoidCallback onHeartTap;
  final VoidCallback onContinue;
  final VoidCallback onStartNew;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
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
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight:
                    AppSizes.discoveryLayerBarHeight -
                    AppSizes.discoveryLayerBarCollapsedHeight,
                maxHeight:
                    AppSizes.discoveryLayerBarHeight -
                    AppSizes.discoveryLayerBarCollapsedHeight,
                child: SizedBox(
                  height:
                      AppSizes.discoveryLayerBarHeight -
                      AppSizes.discoveryLayerBarCollapsedHeight,
                  child: _body(),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _body() {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: AppSizes.iconMedium,
          height: AppSizes.iconMedium,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (errorMessage != null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        message: errorMessage!,
      );
    }
    if (showResumePrompt) {
      return _ResumePrompt(
        stateName: stateName,
        savedCardCount: savedCardCount,
        savedLikeCount: savedLikeCount,
        savedRestaurantCount: savedRestaurantCount,
        onContinue: onContinue,
        onStartNew: onStartNew,
      );
    }
    final LocalFood? food = currentFood;
    if (food == null) {
      return const _MessageState(
        icon: Icons.restaurant_menu,
        message: 'No local food with a serving location was found here.',
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (DragEndDetails details) {
        final double velocity = details.primaryVelocity ?? 0;
        if (velocity < -80 && nextFood != null) onNext();
        if (velocity > 80 && previousFood != null) onPrevious();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gapWidth = AppSpacing.sm * 2;
            const double naturalQueueWidth =
                AppSizes.discoveryQueueCardWidth * 0.45;
            const double naturalTotalWidth =
                AppSizes.discoveryTargetCardWidth +
                naturalQueueWidth * 2 +
                gapWidth;
            final double scale = constraints.maxWidth < naturalTotalWidth
                ? constraints.maxWidth / naturalTotalWidth
                : 1;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _QueueCard(
                  food: previousFood,
                  onTap: onPrevious,
                  width: naturalQueueWidth * scale,
                ),
                SizedBox(width: AppSpacing.sm * scale),
                _TargetFoodCard(
                  food: food,
                  restricted: currentFoodRestricted,
                  liked: currentFoodLiked,
                  likeRevision: likeRevision,
                  width: AppSizes.discoveryTargetCardWidth * scale,
                  onTap: () => onFoodTap(food),
                  onLike: onLike,
                  onHeartTap: onHeartTap,
                ),
                SizedBox(width: AppSpacing.sm * scale),
                _QueueCard(
                  food: nextFood,
                  onTap: onNext,
                  width: naturalQueueWidth * scale,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onToggle,
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
            height: AppSpacing.xs,
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
                size: AppSizes.iconSmall,
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

class _TargetFoodCard extends StatelessWidget {
  const _TargetFoodCard({
    required this.food,
    required this.restricted,
    required this.liked,
    required this.likeRevision,
    required this.onTap,
    required this.width,
    required this.onLike,
    required this.onHeartTap,
  });

  final LocalFood food;
  final bool restricted;
  final bool liked;
  final int likeRevision;
  final VoidCallback onTap;
  final double width;
  final VoidCallback onLike;
  final VoidCallback onHeartTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('swipe-target-card'),
    onTap: onTap,
    onDoubleTap: onLike,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: restricted ? 0.55 : 1,
      child: Container(
        width: width,
        height: AppSizes.discoveryTargetCardHeight * 0.7,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: restricted ? AppColors.textDisabled : AppColors.primary,
            width: 2,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _FoodImage(food: food)),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        food.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall,
                      ),
                      Text(
                        restricted
                            ? 'Dietary caution • placed last'
                            : 'Double tap to match',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: restricted
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: IconButton(
                key: const Key('swipe-like-button'),
                tooltip: liked ? 'Already matched' : 'Like this food',
                onPressed: onHeartTap,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) =>
                          ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey<String>('like-$liked-$likeRevision'),
                    color: liked ? AppColors.error : AppColors.surface,
                    size: AppSizes.iconMedium,
                    shadows: const <Shadow>[
                      Shadow(color: AppColors.scrim, blurRadius: AppSpacing.xs),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.food,
    required this.onTap,
    required this.width,
  });

  final LocalFood? food;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: food == null
        ? const SizedBox.shrink()
        : GestureDetector(
            onTap: onTap,
            child: Container(
              height: AppSizes.discoveryQueueCardHeight * 0.62,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  Expanded(child: _FoodImage(food: food!)),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Text(
                      food!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

class _FoodImage extends StatelessWidget {
  const _FoodImage({required this.food});

  final LocalFood food;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = food.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return _fallback();
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() => const ColoredBox(
    color: AppColors.surfaceVariant,
    child: Center(child: Icon(Icons.restaurant_menu, color: AppColors.primary)),
  );
}

class _ResumePrompt extends StatelessWidget {
  const _ResumePrompt({
    required this.stateName,
    required this.savedCardCount,
    required this.savedLikeCount,
    required this.savedRestaurantCount,
    required this.onContinue,
    required this.onStartNew,
  });

  final String stateName;
  final int savedCardCount;
  final int savedLikeCount;
  final int savedRestaurantCount;
  final VoidCallback onContinue;
  final VoidCallback onStartNew;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          'Continue your $stateName session?',
          style: AppTextStyles.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: <Widget>[
            Text('$savedCardCount cards', style: AppTextStyles.bodySmall),
            Text('$savedLikeCount liked', style: AppTextStyles.bodySmall),
            Text(
              '$savedRestaurantCount restaurants',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: onStartNew,
                child: const Text('Start New'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppSpacing.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _MatchesPill extends StatelessWidget {
  const _MatchesPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.secondary,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    elevation: AppSizes.cardElevation,
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
              style: AppTextStyles.compactBadgeLabel.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
