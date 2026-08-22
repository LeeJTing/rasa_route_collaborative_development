import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/local_food.dart';

/// Reusable piece of `FoodRecognitionView`: the "Local Food Recognised"
/// result content shown inside the popup after a successful food-photo
/// capture. Used for both the primary capture (with "View Details" and a
/// link to `AddLandmarkView`) and "Add More Food" (A12, no "View Details", a
/// different confirm label - see [addLandmarkLabel]/[promptText]).
///
/// Keeps this preview brief on purpose - just Dish, Variant and a
/// one-line-truncated description, inside a highlighted box. Everything
/// else (Origin, Food Category, Meal Type, Taste, Cooking Style, Cultural
/// Background) is one tap away via "View Details"
/// (`RecognisedFoodDetailsView`), not crammed into this popup.
///
/// No outer `Card` here on purpose - `FoodRecognitionView` wraps every popup
/// state (this, loading, error, image-capture-confirm) in one shared card,
/// so this widget is just the content that goes inside it. No "capture
/// again" button either - the popup's shared close (X) button is the one way
/// back to the live camera, everywhere in that popup.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values. Promote one to
/// `lib/views/common_widgets/` once a second screen needs it.
class RecognitionResultCard extends StatelessWidget {
  const RecognitionResultCard({
    super.key,
    required this.food,
    this.capturedImage,
    this.onViewDetails,
    this.onAddLandmark,
    this.addLandmarkLabel = 'Add New Landmark',
    this.promptText = 'Would you like to add this as a new landmark?',
  });

  final LocalFood food;

  /// The photo the tourist just took, shown as a small thumbnail next to the
  /// recognised details.
  final XFile? capturedImage;

  final VoidCallback? onViewDetails;
  final VoidCallback? onAddLandmark;

  /// Label on the primary confirm button - "Add New Landmark" for the
  /// primary capture, "Add to Landmark" for "Add More Food" (A12).
  final String addLandmarkLabel;

  /// Text shown above the confirm button, matching whichever label is used.
  final String promptText;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: AppSpacing.cardPadding,
            decoration: const BoxDecoration(
              color: AppColors.recognitionHighlight,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: AppSpacing.sm),
                    const Flexible(
                      child: Text(
                        'Local Food Recognised',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (capturedImage != null) ...<Widget>[
                      _Thumbnail(image: capturedImage!),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _InfoRow(label: 'Dish', value: food.name),
                          if (food.synonyms.isNotEmpty)
                            _InfoRow(label: 'Variant', value: food.synonyms.first),
                          if (food.description.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _truncateDescription(food.description),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: AppTextStyles.recognitionInfoValue,
                            ),
                          ],
                          if (onViewDetails != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            _ViewDetailsLink(onTap: onViewDetails!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            promptText,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (onAddLandmark != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAddLandmark,
                child: Text(addLandmarkLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// Truncates a description to a short one-line preview, always appending a
/// literal "..." - even when it isn't hard-truncated by length, since this
/// is a preview inviting a tap into "View Details" for the rest, not the
/// complete text either way.
String _truncateDescription(String description, {int maxLength = 40}) {
  final String trimmed = description.trim();
  final String preview =
      trimmed.length <= maxLength ? trimmed : trimmed.substring(0, maxLength).trimRight();
  return '$preview ...';
}

class _ViewDetailsLink extends StatelessWidget {
  const _ViewDetailsLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'View Details',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.image});

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
              child: ColoredBox(color: AppColors.surface),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: AppSizes.fieldLabelWidthCompact,
            child: Text(label, style: AppTextStyles.detailLabel),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: AppTextStyles.recognitionInfoValue,
            ),
          ),
        ],
      ),
    );
  }
}
