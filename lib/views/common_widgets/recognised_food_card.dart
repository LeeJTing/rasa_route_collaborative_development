import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/local_food.dart';

/// The "Recognised Food" card - the same card shown on `AddLandmarkView`
/// ("Form 1") and `LandmarkDetailView` ("View Details"). Thumbnail on the
/// left, Dish/Variant/Origin/Food Category/Meal Type as one field list on
/// the right (Food Category/Meal Type rendered as small coloured pills),
/// with the fuller details (Description/Cooking Style/Cultural Background)
/// below.
///
/// [collapsible] - on `AddLandmarkView` those fuller details start collapsed
/// behind an expand/collapse arrow; on `LandmarkDetailView` they are shown
/// always expanded with no arrow.
///
/// [footer] - optional widget rendered at the bottom inside the card (e.g.
/// `AddLandmarkView`'s Price field). `LandmarkDetailView` passes none.
///
/// Shared because two screens render the same card (this project's
/// convention: promote a screen-local widget to `lib/views/common_widgets/`
/// once a second screen needs it). Driven entirely by constructor parameters
/// and callbacks - it never reads a ViewModel itself, and styles from the
/// theme rather than raw values.
class RecognisedFoodCard extends StatefulWidget {
  const RecognisedFoodCard({
    super.key,
    required this.food,
    this.image,
    this.collapsible = false,
    this.footer,
  });

  final LocalFood food;
  final XFile? image;
  final bool collapsible;
  final Widget? footer;

  @override
  State<RecognisedFoodCard> createState() => _RecognisedFoodCardState();
}

class _RecognisedFoodCardState extends State<RecognisedFoodCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final LocalFood food = widget.food;
    final bool showDetails = !widget.collapsible || _expanded;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Recognised Food',
                    style: AppTextStyles.titleSmall,
                  ),
                ),
                if (widget.collapsible)
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (widget.image != null) ...<Widget>[
                  _FoodThumbnail(image: widget.image!),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _FieldRow(label: 'Dish', value: food.name),
                      if (food.synonyms.isNotEmpty)
                        _FieldRow(label: 'Variant', value: food.synonyms.first),
                      _FieldRow(label: 'Origin', value: food.origin),
                      _ChipFieldRow(
                        label: 'Food Category',
                        value: food.category,
                        background: AppColors.secondaryContainer,
                      ),
                      _ChipFieldRow(
                        label: 'Meal Type',
                        value: food.mealType,
                        background: AppColors.primaryContainer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showDetails) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              // if (food.taste.isNotEmpty) ...<Widget>[
              //   _ExpandedTasteTags(tags: food.taste),
              //   const SizedBox(height: AppSpacing.sm),
              // ],
              if (food.description.isNotEmpty) ...<Widget>[
                _ExpandedTextField(
                  label: 'Description',
                  value: food.description,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (food.cookingStyle.isNotEmpty) ...<Widget>[
                _ExpandedTextField(
                  label: 'Cooking Style',
                  value: food.cookingStyle,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (food.culturalBackground.isNotEmpty)
                _ExpandedTextField(
                  label: 'Cultural Background',
                  value: food.culturalBackground,
                ),
            ],
            if (widget.footer != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              widget.footer!,
            ],
          ],
        ),
      ),
    );
  }
}

// /// Taste tags, shown in the expanded details - chip styling per the theme.
// class _ExpandedTasteTags extends StatelessWidget {
//   const _ExpandedTasteTags({required this.tags});

//   final List<String> tags;

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: <Widget>[
//         Text('Taste', style: AppTextStyles.detailLabel),
//         const SizedBox(height: AppSpacing.xs),
//         Wrap(
//           spacing: AppSpacing.xs,
//           runSpacing: AppSpacing.xs,
//           children: <Widget>[
//             for (final String tag in tags)
//               Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: AppSpacing.sm,
//                   vertical: AppSpacing.xs,
//                 ),
//                 decoration: BoxDecoration(
//                   color: AppColors.tasteTagBackground,
//                   borderRadius: BorderRadius.circular(AppRadius.pill),
//                 ),
//                 child: Text(tag, style: AppTextStyles.tasteTag),
//               ),
//           ],
//         ),
//       ],
//     );
//   }
// }

/// A label-above-value field for the longer details (Description, Cooking
/// Style, Cultural Background).
class _ExpandedTextField extends StatelessWidget {
  const _ExpandedTextField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.detailLabel),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTextStyles.detailValue),
      ],
    );
  }
}

/// Small square photo thumbnail beside the field list.
class _FoodThumbnail extends StatelessWidget {
  const _FoodThumbnail({required this.image});

  final XFile image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: FutureBuilder<Uint8List>(
        future: image.readAsBytes(),
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              width: AppSizes.avatarLg,
              height: AppSizes.avatarLg,
              child: ColoredBox(color: AppColors.surfaceVariant),
            );
          }
          return Image.memory(
            snapshot.data!,
            width: AppSizes.avatarLg,
            height: AppSizes.avatarLg,
            fit: BoxFit.cover,
          );
        },
      ),
    );
  }
}

/// Inline label/value row - `'Dish  Nasi Lemak'` in one text span.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '$label  ', style: AppTextStyles.detailLabel),
            TextSpan(
              text: value.isEmpty ? '-' : value,
              style: AppTextStyles.detailValue,
            ),
          ],
        ),
      ),
    );
  }
}

/// Food Category / Meal Type, shown inline with their label as a small
/// coloured pill. No explicit hex was given for these two - reusing the
/// existing [AppColors.secondaryContainer] / [AppColors.primaryContainer]
/// brand tokens; flag if specific Figma values exist for them.
class _ChipFieldRow extends StatelessWidget {
  const _ChipFieldRow({
    required this.label,
    required this.value,
    required this.background,
  });

  final String label;
  final String value;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: AppSizes.fieldLabelWidth,
            child: Text(label, style: AppTextStyles.detailLabel),
          ),
          // Flexible so a long value (e.g. "All-Day Dining") never overflows
          // the card's right edge - the pill shrinks and ellipsizes instead.
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.detailValue.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
