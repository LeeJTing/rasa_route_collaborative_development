import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import 'dietary_status_badge.dart';

class ComparisonPairCard extends StatelessWidget {
  const ComparisonPairCard({
    required this.comparison,
    this.onPlayPronunciation,
    this.playingPronunciationFoodIds = const <int>{},
    super.key,
  });

  final FoodComparison comparison;
  final Future<void> Function(LocalFood food)? onPlayPronunciation;
  final Set<int> playingPronunciationFoodIds;

  @override
  Widget build(BuildContext context) {
    final LocalFood left = comparison.leftFood;
    final LocalFood right = comparison.rightFood;

    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.outline),
          borderRadius: AppRadius.cardRadius,
        ),
        child: Column(
          children: <Widget>[
            _PairRow(
              left: _FoodHeader(food: left),
              right: _FoodHeader(food: right),
              padded: true,
            ),
            _ComparisonSection(
              title: 'How to say it',
              icon: Icons.record_voice_over_rounded,
              left: _PronunciationTile(
                food: left,
                playing: playingPronunciationFoodIds.contains(left.id),
                busy: playingPronunciationFoodIds.isNotEmpty,
                onPlayPronunciation: onPlayPronunciation,
              ),
              right: _PronunciationTile(
                food: right,
                playing: playingPronunciationFoodIds.contains(right.id),
                busy: playingPronunciationFoodIds.isNotEmpty,
                onPlayPronunciation: onPlayPronunciation,
              ),
            ),
            _ComparisonSection(
              title: 'Dietary safety',
              icon: Icons.health_and_safety_rounded,
              left: DietaryStatusBadge(
                assessment: comparison.leftDietaryAssessment,
              ),
              right: DietaryStatusBadge(
                assessment: comparison.rightDietaryAssessment,
              ),
            ),
            _ComparisonSection(
              title: 'Ingredients & allergens',
              icon: Icons.list_alt_rounded,
              left: _BulletList(items: _splitIngredients(left.ingredients)),
              right: _BulletList(items: _splitIngredients(right.ingredients)),
            ),
            _ComparisonSection(
              title: 'Origin & heritage',
              icon: Icons.public_rounded,
              left: _LabeledText(
                label: left.origin,
                value: left.culturalBackground,
              ),
              right: _LabeledText(
                label: right.origin,
                value: right.culturalBackground,
              ),
            ),
            _ComparisonSection(
              title: 'Cooking style',
              icon: Icons.soup_kitchen_rounded,
              left: Text(left.cookingStyle),
              right: Text(right.cookingStyle),
            ),
            _ComparisonSection(
              title: 'Time and Price',
              icon: Icons.schedule_rounded,
              left: _TimeAndPrice(
                mealType: left.mealType,
                priceRange: comparison.priceByFoodId[left.id],
              ),
              right: _TimeAndPrice(
                mealType: right.mealType,
                priceRange: comparison.priceByFoodId[right.id],
              ),
            ),
            _ComparisonSection(
              title: 'What to expect',
              icon: Icons.reviews_rounded,
              left: Text(left.description),
              right: Text(right.description),
            ),
          ],
        ),
      ),
    );
  }
}

class _PronunciationTile extends StatelessWidget {
  const _PronunciationTile({
    required this.food,
    required this.playing,
    required this.busy,
    required this.onPlayPronunciation,
  });

  final LocalFood food;
  final bool playing;

  /// True while ANY dish's pronunciation is playing - disables the button so
  /// only one playback can run at a time (same as the food detail page).
  final bool busy;
  final Future<void> Function(LocalFood food)? onPlayPronunciation;

  @override
  Widget build(BuildContext context) {
    final Future<void> Function(LocalFood food)? play = onPlayPronunciation;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            food.pronunciationText.isEmpty ? food.name : food.pronunciationText,
            // Same body style as the ingredients / description rows.
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (play != null)
          IconButton(
            tooltip: 'Play pronunciation',
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : () => play(food),
            icon: playing
                ? const SizedBox.square(
                    dimension: AppSizes.iconSmall,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.volume_up_rounded, size: AppSizes.iconSmall),
          ),
      ],
    );
  }
}

class _FoodHeader extends StatefulWidget {
  const _FoodHeader({required this.food});

  final LocalFood food;

  @override
  State<_FoodHeader> createState() => _FoodHeaderState();
}

class _FoodHeaderState extends State<_FoodHeader> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final List<String> images = widget.food.imageUrls;
    return Column(
      children: <Widget>[
        SizedBox(
          height: AppSizes.comparisonImageHeight,
          width: double.infinity,
          child: images.length > 1
              ? Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (int index) {
                          setState(() => _page = index);
                        },
                        itemBuilder: (BuildContext context, int index) =>
                            AppImage(
                              source: images[index],
                              semanticLabel: '${widget.food.name} image '
                                  '${index + 1} of ${images.length}',
                            ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.scrim,
                          borderRadius: BorderRadius.all(
                            Radius.circular(AppRadius.pill),
                          ),
                        ),
                        child: Text(
                          '${_page + 1}/${images.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.surface),
                        ),
                      ),
                    ),
                  ],
                )
              : AppImage(source: widget.food.imageUrl),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.food.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.food.category,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({
    required this.title,
    required this.icon,
    required this.left,
    required this.right,
  });

  final String title;
  final IconData icon;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            // FFE082 at 100%.
            color: AppColors.cardBorderWarm,
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: AppSizes.iconSmall,
                  color: AppColors.accentBrown,
                ),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          _PairRow(left: left, right: right, padded: true),
        ],
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({
    required this.left,
    required this.right,
    required this.padded,
  });

  final Widget left;
  final Widget right;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final EdgeInsetsGeometry padding = padded
        ? const EdgeInsets.all(AppSpacing.md)
        : EdgeInsets.zero;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: Padding(padding: padding, child: left)),
          Expanded(child: Padding(padding: padding, child: right)),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Ingredients not recorded.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (String item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('• $item'),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value),
      ],
    );
  }
}

/// One side of the "Time and Price" comparison section - shows when the dish
/// is best eaten and its restaurant price range.
class _TimeAndPrice extends StatelessWidget {
  const _TimeAndPrice({required this.mealType, this.priceRange});

  final String mealType;

  /// The real lowest/highest listed price for this dish, or null when the
  /// dish appears on no restaurant menu.
  final ({double min, double max})? priceRange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MiniFact(
          label: 'Best eaten',
          value: mealType.isEmpty ? 'Any time' : mealType,
        ),
        const SizedBox(height: AppSpacing.md),
        _MiniFact(
          label: 'Price per serving',
          value: _priceLabel(priceRange),
          valueColor: priceRange == null
              ? AppColors.textSecondary
              : AppColors.accentRust,
        ),
      ],
    );
  }

  /// "RM 5.00 - RM 12.00" (or "RM 5.00" when every seller charges the same),
  /// "Not listed yet" when the dish is on no restaurant menu.
  static String _priceLabel(({double min, double max})? range) {
    if (range == null) return 'Not listed yet';
    final String min = range.min.toStringAsFixed(2);
    final String max = range.max.toStringAsFixed(2);
    return min == max ? 'RM $min' : 'RM $min - RM $max';
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Splits the repository's raw ingredients string (comma / semicolon / a
/// JSON-array-shaped blob) into bullet-list entries.
List<String> _splitIngredients(String raw) => raw
    .replaceAll(RegExp(r'[\[\]"]'), '')
    .split(RegExp(r'[,;/]'))
    .map((String part) => part.trim())
    .where((String part) => part.isNotEmpty)
    .toList(growable: false);
