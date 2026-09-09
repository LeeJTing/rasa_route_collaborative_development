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
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_scrollController.hasClients || widget.foods.isEmpty) return;
      _currentIndex = (_currentIndex + 1) % widget.foods.length;
      final double itemWidth = AppSizes.recommendationImage + AppSpacing.md;
      _scrollController.animateTo(
        _currentIndex * itemWidth,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSizes.recommendationImage + AppSpacing.xxl,
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
  );
}
