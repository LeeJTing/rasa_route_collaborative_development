import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import 'dietary_status_badge.dart';

/// A multi-unit pack detected inside a menu-line name (e.g. "BOTOL 30").
class _BulkPack {
  const _BulkPack({required this.count, required this.unit});

  final int count;
  final String unit;
}

final RegExp _bulkPackPattern = RegExp(
  r'(?:'
  r'(\d+)\s*\b(botol|biji|pek|paket|pak|kotak|tin|karton|dozen|lusin|bungkus|set|pcs?|pieces?)\b'
  r'|\b(botol|biji|pek|paket|pak|kotak|tin|karton|dozen|lusin|bungkus|set|pcs?|pieces?)\b\s*(\d+)'
  r')',
  caseSensitive: false,
);

/// Parses [name] as a bulk pack (count > 1) or returns null. A count of 1
/// (e.g. "BOTOL 1") is a normal single serve, not a bulk pack.
_BulkPack? _bulkPackFrom(String name) {
  final RegExpMatch? match = _bulkPackPattern.firstMatch(name);
  if (match == null) return null;
  final String? count = match.group(1) ?? match.group(4);
  final String? unit = match.group(2) ?? match.group(3);
  final int? parsed = int.tryParse(count ?? '');
  if (unit == null || parsed == null || parsed <= 1) return null;
  return _BulkPack(count: parsed, unit: unit.toLowerCase());
}


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
                menuItems:
                    comparison.menuItemsByFoodId[left.id] ??
                    const <({String name, double price})>[],
              ),
              right: _TimeAndPrice(
                mealType: right.mealType,
                menuItems:
                    comparison.menuItemsByFoodId[right.id] ??
                    const <({String name, double price})>[],
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
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.accentBrown,
            ),
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
  void didUpdateWidget(_FoodHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A quick-switch can replace this slot's dish, so never keep a gallery
    // page index that belonged to the previous one.
    if (oldWidget.food.id != widget.food.id) _page = 0;
  }

  Future<void> _showGallery(
    BuildContext context,
    List<String> images,
    int initialIndex,
  ) => showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (BuildContext dialogContext) => Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: AppColors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: images.length,
            itemBuilder: (BuildContext context, int index) =>
                InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: AppImage(
                      source: images[index],
                      fit: BoxFit.contain,
                      semanticLabel: '${widget.food.name} image '
                          '${index + 1} of ${images.length}',
                    ),
                  ),
                ),
          ),
          Positioned(
            top: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Close image',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final List<String> images = widget.food.imageUrls;
    final bool hasImages = images.isNotEmpty;
    final int page = hasImages && _page < images.length ? _page : 0;
    return Column(
      children: <Widget>[
        Semantics(
          button: hasImages,
          label: 'Enlarge ${widget.food.name} photo',
          child: InkWell(
            onTap: hasImages
                ? () => _showGallery(context, images, page)
                : null,
            child: SizedBox(
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
                              '${page + 1}/${images.length}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.surface),
                            ),
                          ),
                        ),
                      ],
                    )
                  : AppImage(source: widget.food.imageUrl),
            ),
          ),
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

/// One side of the "Time and Price" comparison section. Prices are shown as
/// ONE range: single-serving lines as-is, and bulk-pack lines normalised to a
/// per-unit price (price / count), so a "BOTOL 30 = RM540" line counts as
/// RM18 per botol instead of inflating the max.
class _TimeAndPrice extends StatelessWidget {
  const _TimeAndPrice({
    required this.mealType,
    this.menuItems = const <({String name, double price})>[],
  });

  final String mealType;

  /// Every real menu line (name + price) for this dish.
  final List<({String name, double price})> menuItems;

  @override
  Widget build(BuildContext context) {
    final List<double> perServing = <double>[];
    for (final ({String name, double price}) entry in menuItems) {
      final _BulkPack? pack = _bulkPackFrom(entry.name);
      // Bulk lines are folded into the same range at their per-unit price.
      perServing.add(pack == null ? entry.price : entry.price / pack.count);
    }
    final String? range = _doublesRange(perServing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MiniFact(
          label: 'Best eaten',
          value: mealType.isEmpty ? 'Any time' : mealType,
        ),
        const SizedBox(height: AppSpacing.md),
        _MiniFact(
          label: 'Price',
          value: range ?? 'Not listed at any restaurant yet',
          valueColor: range == null
              ? AppColors.textSecondary
              : AppColors.accentRust,
        ),
      ],
    );
  }

  static String? _doublesRange(List<double> values) {
    if (values.isEmpty) return null;
    double min = values.first;
    double max = min;
    for (final double value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final String lo = min.toStringAsFixed(2);
    final String hi = max.toStringAsFixed(2);
    return lo == hi ? 'RM $lo' : 'RM $lo - RM $hi';
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
