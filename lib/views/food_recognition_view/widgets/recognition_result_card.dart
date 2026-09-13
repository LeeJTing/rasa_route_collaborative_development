import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/dietary_conflict_warning.dart';
import 'manual_food_name_entry.dart';

/// Reusable piece of `FoodRecognitionView`: the "Local Food Recognised"
/// result content shown inside the popup after a successful food-photo
/// capture. Used for both the primary capture (with "View Details" and a
/// link to `AddLandmarkView`) and "Add More Food" (A12, no "View Details", a
/// different confirm label - see [addLandmarkLabel]/[promptText]).
///
/// Keeps this preview brief on purpose - just Dish, Variant and a labelled,
/// wrapped description (up to a few lines), inside a highlighted box.
/// Everything else (Origin, Food Category, Meal Type, Taste, Cooking Style,
/// Cultural Background) is one tap away via "View Details"
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
    this.variant = '',
    this.capturedImage,
    this.onViewDetails,
    this.onAddLandmark,
    this.isLocalFood = true,
    this.fitsCatalogueCategory = true,
    this.isLowConfidence = false,
    this.onEnterName,
    required this.foodNameMaxLength,
    required this.foodNameWarning,
    this.isProcessing = false,
    this.addLandmarkLabel = 'Add New Landmark',
    this.promptText = 'Would you like to add this as a new landmark?',
    this.nameMismatch = false,
    this.typedName,
    this.onDismissNameMismatch,
    this.dietaryConflicts = const <String>[],
    this.blockMessage,
  });

  final LocalFood food;

  /// The VARIANT name the dish was actually seen/typed as when it EXTENDS
  /// the dictionary [food] into an unlisted variant (`Cendol Jagung` ->
  /// `Cendol`) - shown as the card's "Variant" row; empty hides the row.
  /// Carried from `FoodRecognitionViewModel.variant`.
  final String variant;

  /// The photo the tourist just took, shown as a small thumbnail next to the
  /// recognised details.
  final XFile? capturedImage;

  final VoidCallback? onViewDetails;
  final VoidCallback? onAddLandmark;

  /// Whether the food is Malaysian local food. When false the header switches
  /// to a "Not Local" warning and the caller must not pass [onAddLandmark] -
  /// the details are still shown and "View Details" still works.
  final bool isLocalFood;

  /// Whether the food fits a catalogue dish type (Food/Beverage/Fruit/
  /// Dessert/Kuih). When false it is a Malaysian product at most (snack,
  /// package, canned drink) - the header shows a "Malaysian Product" warning
  /// and the caller must not pass [onAddLandmark].
  final bool fitsCatalogueCategory;

  /// Whether the recognition was shaky enough that the tourist should be
  /// asked to verify it - the card shows a "low confidence" cue when true.
  /// An already-decided boolean, not a raw score: the threshold is a domain
  /// rule and lives in `FoodRecognitionLogic.isLowConfidence`, surfaced
  /// through `FoodRecognitionViewModel.isLowConfidence`. This widget only
  /// decides how to draw it.
  final bool isLowConfidence;

  /// Whether a manually-typed name was verified against the photo and found
  /// NOT to match it - the card warns "this photo doesn't look like X, it
  /// looks like Y" and the typed name can NOT be added (only the detected
  /// food can be kept).
  final bool nameMismatch;

  /// The name the tourist typed, shown in the mismatch warning ("This
  /// photo doesn't look like `<typed>`...", with the card's own dish as what
  /// it looks like instead).
  final String? typedName;

  /// "Keep the detected food" - the only action on a mismatch warning; the
  /// typed name (which Gemini could not confirm) is never applied. The
  /// button names the food being KEPT (this card's own dish), never the
  /// verification call's observation - the observation names a third dish
  /// that the app does not switch to.
  final VoidCallback? onDismissNameMismatch;

  /// The signed-in tourist's dietary restrictions this recognised food
  /// conflicts with (e.g. "No Pork"). When non-empty a warning is shown -
  /// the food can still be added.
  final List<String> dietaryConflicts;

  /// Why this capture cannot join the landmark at all (e.g. it was taken
  /// more than 50 m from the first food, so it is not the same restaurant -
  /// see `FoodRecognitionViewModel.captureRangeError`). When non-null the
  /// reason is shown and [onAddLandmark] must be null: the only way forward
  /// is capturing again on site.
  final String? blockMessage;

  /// Manual fallback when Gemini got the dish wrong - called with the food
  /// name the tourist typed (see `FoodRecognitionViewModel.enterFoodName`).
  /// Null hides the "type the name" option.
  final ValueChanged<String>? onEnterName;

  /// Hard input cap for the manual name field (50) - the shared
  /// `LandmarkSubmissionLogic.maxFoodNameLength` rule, surfaced by
  /// `FoodRecognitionViewModel.foodNameMaxLength`.
  final int foodNameMaxLength;

  /// Live amber warning for the typed name (null while it is a normal
  /// length) - `FoodRecognitionViewModel.foodNameWarning`.
  final String? Function(String name) foodNameWarning;

  /// Disables the manual-entry field/button while a name is being resolved.
  final bool isProcessing;

  /// Label on the primary confirm button - "Add New Landmark" for the
  /// primary capture, "Add to Landmark" for "Add More Food" (A12).
  final String addLandmarkLabel;

  /// Text shown above the confirm button, matching whichever label is used.
  /// Null hides the line entirely - used when a blocked capture's warning
  /// box already carries both the reason and the action, so nothing is
  /// repeated.
  final String? promptText;

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
                    Icon(
                      isLocalFood && fitsCatalogueCategory
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: isLocalFood && fitsCatalogueCategory
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        isLocalFood && fitsCatalogueCategory
                            ? 'Local Food Recognised'
                            : !isLocalFood
                            ? 'Food Detected (Not Local)'
                            : 'Malaysian Product Detected',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (isLocalFood && isLowConfidence) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(
                        Icons.help_outline,
                        size: AppSizes.inlineNoticeIconSize,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Low confidence - please verify this dish',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (nameMismatch &&
                    typedName != null &&
                    typedName!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.error_outline,
                              size: AppSizes.inlineNoticeIconSize,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                // Two names only: what was typed, and the
                                // recognised dish that stays - never the
                                // verification call's raw observation (a
                                // third name that made the warning
                                // contradict the keep button).
                                "This photo doesn't look like "
                                "'${typedName!}' - it looks more "
                                "like '${food.name}', so "
                                "it can't be added as "
                                "'${typedName!}'.",
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (onDismissNameMismatch != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              TextButton(
                                onPressed: onDismissNameMismatch,
                                // The dish that is actually kept - never
                                // [observedFoodName] (the fresh observation
                                // the app does NOT switch to; naming it here
                                // made the app look like it forgot the
                                // detected dish).
                                child: Text("Keep '${food.name}'"),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
                if (dietaryConflicts.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  DietaryConflictWarning(conflicts: dietaryConflicts),
                ],
                if (blockMessage != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  _BlockedCaptureWarning(message: blockMessage!),
                ],
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
                          if (variant.isNotEmpty)
                            _InfoRow(label: 'Variant', value: variant),
                          if (food.description.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            // Labelled like every other field on the card -
                            // the bare paragraph read as if the word
                            // "Description" had been dropped.
                            Text(
                              'Description',
                              style: AppTextStyles.detailLabel,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            // The FULL description, wrapped: the column next
                            // to the 96 pt thumbnail has room for several
                            // lines (all of them when no Variant row is
                            // shown), so the old 40-character one-line
                            // preview just left the space empty. Long text
                            // ellipsizes - "View Details" opens the rest.
                            Text(
                              food.description.trim(),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
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
          if (promptText != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              promptText!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (onAddLandmark != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAddLandmark,
                child: Text(addLandmarkLabel),
              ),
            ),
          if (onEnterName != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            ManualFoodNameEntry(
              onEnterName: onEnterName!,
              isProcessing: isProcessing,
              maxNameLength: foodNameMaxLength,
              nameWarning: foodNameWarning,
            ),
          ],
        ],
      ),
    );
  }
}

/// Warning box: this capture cannot join the landmark at all - it was taken
/// too far from the first food, so it is not the same restaurant (blocking,
/// unlike the dietary warning). The only way forward is capturing again on
/// site.
class _BlockedCaptureWarning extends StatelessWidget {
  const _BlockedCaptureWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bannerCautionBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.location_off,
            size: AppSizes.inlineNoticeIconSize,
            color: AppColors.bannerCautionText,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.bannerCautionText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
