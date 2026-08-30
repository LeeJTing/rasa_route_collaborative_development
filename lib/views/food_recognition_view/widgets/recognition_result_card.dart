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
    this.isLocalFood = true,
    this.fitsCatalogueCategory = true,
    this.isLowConfidence = false,
    this.onEnterName,
    this.isProcessing = false,
    this.addLandmarkLabel = 'Add New Landmark',
    this.promptText = 'Would you like to add this as a new landmark?',
    this.nameMismatch = false,
    this.observedFoodName,
    this.typedName,
    this.onDismissNameMismatch,
  });

  final LocalFood food;

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

  /// What the photo actually shows, in Gemini's words, when [nameMismatch].
  final String? observedFoodName;

  /// The name the tourist typed, shown as the alternative in the mismatch
  /// warning ("This looks more like X than `<typedName>`.").
  final String? typedName;

  /// "Keep the detected food" - the only action on a mismatch warning; the
  /// typed name (which Gemini could not confirm) is never applied.
  final VoidCallback? onDismissNameMismatch;

  /// Manual fallback when Gemini got the dish wrong - called with the food
  /// name the tourist typed (see `FoodRecognitionViewModel.enterFoodName`).
  /// Null hides the "type the name" option.
  final ValueChanged<String>? onEnterName;

  /// Disables the manual-entry field/button while a name is being resolved.
  final bool isProcessing;

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
                    observedFoodName != null &&
                    observedFoodName!.isNotEmpty) ...<Widget>[
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
                                "This photo doesn't look like "
                                "'${typedName ?? food.name}' - it looks more "
                                "like '${observedFoodName ?? food.name}', so "
                                "it can't be added as "
                                "'${typedName ?? food.name}'.",
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
                                child: Text(
                                  "Keep '${observedFoodName ?? food.name}'",
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
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
                          if (food.synonyms.isNotEmpty)
                            _InfoRow(
                              label: 'Variant',
                              value: food.synonyms.first,
                            ),
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
          if (onEnterName != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _ManualNameEntryField(
              onEnterName: onEnterName!,
              isProcessing: isProcessing,
            ),
          ],
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
  final String preview = trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength).trimRight();
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

/// "Wrong dish? Type the name" - a small, collapsible manual-entry field
/// appended to the single-result card. Lets the tourist override Gemini's
/// answer by typing the food name (see
/// `FoodRecognitionViewModel.enterFoodName`).
class _ManualNameEntryField extends StatefulWidget {
  const _ManualNameEntryField({
    required this.onEnterName,
    required this.isProcessing,
  });

  final ValueChanged<String> onEnterName;
  final bool isProcessing;

  @override
  State<_ManualNameEntryField> createState() => _ManualNameEntryFieldState();
}

class _ManualNameEntryFieldState extends State<_ManualNameEntryField> {
  final TextEditingController _controller = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _controller.text.trim();
    if (name.isEmpty || widget.isProcessing) return;
    widget.onEnterName(name);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) {
      return Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: widget.isProcessing
              ? null
              : () => setState(() => _show = true),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Wrong dish? Type the name'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          enabled: !widget.isProcessing,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: 'e.g. Murtabak',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: widget.isProcessing
                  ? null
                  : () => setState(() => _show = false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: widget.isProcessing ? null : _submit,
              child: const Text('Show this food'),
            ),
          ],
        ),
      ],
    );
  }
}
