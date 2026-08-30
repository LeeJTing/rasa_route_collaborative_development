import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

/// A matched local food and all recommendations associated with it.
///
/// Expansion is local presentation state. The widget receives recommendation
/// cards as children and never reads a ViewModel or repository directly.
class MatchedFoodRecommendationGroup extends StatefulWidget {
  const MatchedFoodRecommendationGroup({
    super.key,
    required this.food,
    required this.resultCount,
    required this.children,
    required this.onFoodTap,
    required this.onLikeTap,
    required this.radiusKm,
    required this.canShowMore,
    required this.canShowLess,
    required this.isLoadingMore,
    required this.onShowMore,
    required this.onShowLess,
    this.initiallyExpanded = true,
  });

  final LocalFood food;
  final int resultCount;
  final List<Widget> children;
  final VoidCallback onFoodTap;
  final VoidCallback onLikeTap;
  final double radiusKm;
  final bool canShowMore;
  final bool canShowLess;
  final bool isLoadingMore;
  final VoidCallback onShowMore;
  final VoidCallback onShowLess;
  final bool initiallyExpanded;

  @override
  State<MatchedFoodRecommendationGroup> createState() =>
      _MatchedFoodRecommendationGroupState();
}

class _MatchedFoodRecommendationGroupState
    extends State<MatchedFoodRecommendationGroup> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorderWarm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          InkWell(
            key: ValueKey<String>('matched-food-${widget.food.id}-details'),
            onTap: widget.onFoodTap,
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                children: <Widget>[
                  SizedBox.square(
                    dimension: AppSizes.restaurantCardImage,
                    child: AppImage(
                      source: widget.food.imageUrl,
                      borderRadius: AppRadius.cardRadius,
                      semanticLabel: widget.food.name,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const AppTagChip(
                          label: 'Liked in Swipe Mode',
                          style: AppTagStyle.meal,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          widget.food.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${widget.resultCount} recommendation${widget.resultCount == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        key: ValueKey<String>(
                          'matched-food-${widget.food.id}-like',
                        ),
                        tooltip: 'Remove from Matches',
                        onPressed: widget.onLikeTap,
                        icon: const Icon(
                          Icons.favorite,
                          color: AppColors.error,
                        ),
                      ),
                      IconButton(
                        key: ValueKey<String>(
                          'matched-food-${widget.food.id}-toggle',
                        ),
                        tooltip: _expanded
                            ? 'Collapse recommendations'
                            : 'Expand recommendations',
                        onPressed: _toggleExpanded,
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.accentBrown,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: kThemeAnimationDuration,
            curve: Curves.easeInOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      0,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: AppColors.insetSurface,
                        borderRadius: AppRadius.cardRadius,
                      ),
                      child: Column(
                        children: <Widget>[
                          ..._separatedChildren(),
                          if (widget.children.isNotEmpty &&
                              (widget.canShowMore || widget.canShowLess))
                            const Divider(color: AppColors.outline),
                          if (widget.canShowMore || widget.canShowLess)
                            _pagingActions(),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  List<Widget> _separatedChildren() {
    final List<Widget> separated = <Widget>[];
    for (int index = 0; index < widget.children.length; index += 1) {
      separated.add(widget.children[index]);
      if (index < widget.children.length - 1) {
        separated.add(const Divider(color: AppColors.outline));
      }
    }
    return separated;
  }

  Widget _pagingActions() => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          'Within ${widget.radiusKm.toStringAsFixed(0)} km',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (widget.canShowLess)
        TextButton(
          key: ValueKey<String>('matched-food-${widget.food.id}-show-less'),
          onPressed: widget.onShowLess,
          child: const Text('Show Less'),
        ),
      if (widget.canShowMore)
        TextButton.icon(
          key: ValueKey<String>('matched-food-${widget.food.id}-see-more'),
          onPressed: widget.isLoadingMore ? null : widget.onShowMore,
          icon: widget.isLoadingMore
              ? const SizedBox.square(
                  dimension: AppSpacing.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more),
          label: const Text('See More'),
        ),
    ],
  );

  void _toggleExpanded() => setState(() => _expanded = !_expanded);
}
