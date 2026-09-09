import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';
import '../../domain_model/local_food.dart';
import 'app_image.dart';

class SimilarFoodCard extends StatefulWidget {
  const SimilarFoodCard({super.key, required this.foods, required this.onTap});

  final List<LocalFood> foods;
  final ValueChanged<LocalFood> onTap;

  @override
  State<SimilarFoodCard> createState() => _SimilarFoodCardState();
}

class _SimilarFoodCardState extends State<SimilarFoodCard> {
  static const Duration _autoAdvanceInterval = Duration(seconds: 3);
  static const Duration _idleResumeDelay = Duration(seconds: 4);

  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  Timer? _idleResumeTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startAutoLoop();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _idleResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SimilarFoodCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new dish was selected and its similar list replaced this one - restart
    // the loop from the first item instead of continuing from a stale offset.
    if (!identical(oldWidget.foods, widget.foods)) {
      _currentIndex = 0;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _idleResumeTimer?.cancel();
      _idleResumeTimer = null;
      _startAutoLoop();
    }
  }

  void _startAutoLoop() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(_autoAdvanceInterval, (_) {
      if (!_scrollController.hasClients || widget.foods.isEmpty) return;
      final ScrollPosition position = _scrollController.position;
      if (position.maxScrollExtent <= 0) return;
      final double itemWidth = AppSizes.recommendationImage + AppSpacing.md;
      _currentIndex = (_scrollController.offset / itemWidth)
          .round()
          .clamp(0, widget.foods.length - 1);
      _currentIndex = (_currentIndex + 1) % widget.foods.length;
      _scrollController.animateTo(
        _currentIndex * itemWidth,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseForUserScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _idleResumeTimer?.cancel();
    _idleResumeTimer = Timer(_idleResumeDelay, _resumeAutoLoop);
  }

  void _resumeAutoLoop() {
    _idleResumeTimer?.cancel();
    _idleResumeTimer = null;
    if (!mounted) return;
    _startAutoLoop();
  }

  /// Only genuine finger drags pause the loop. The auto-scroll's own
  /// [ScrollController.animateTo] is a programmatic scroll (no dragDetails),
  /// so it never counts as the tourist taking over.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pauseForUserScroll();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSizes.recommendationImage + AppSpacing.xxl,
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: widget.foods.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final LocalFood food = widget.foods[index];
          return InkWell(
            onTap: () => widget.onTap(food),
            borderRadius: AppRadius.cardRadius,
            child: SizedBox(
              width: AppSizes.recommendationImage,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: AppImage(
                      source: food.imageUrls.isEmpty
                          ? null
                          : food.imageUrls.first,
                      borderRadius: AppRadius.cardRadius,
                      semanticLabel: food.name,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    food.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
