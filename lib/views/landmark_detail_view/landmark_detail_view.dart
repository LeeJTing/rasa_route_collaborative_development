import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/landmark_draft.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/food_recognition_view_model.dart'
    show LandmarkDraftHandoff;
import '../../view_models/landmark_detail_view_model.dart';
import '../common_widgets/add_landmark_reminder_dialog.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/continue_draft_dialog.dart';
import '../common_widgets/recognised_food_card.dart';

/// Landmark detail screen (UC500, A6 "View Details").
///
/// Read-only, full-detail look at the food the tourist just captured -
/// reached from `FoodRecognitionView`'s result popup, or from
/// `AddLandmarkView`'s "Recognised Food" card chevron. Has its own
/// `LandmarkDetailViewModel` (see [LandmarkDetailViewModel.setRecognizedFood]
/// / [LandmarkDetailViewModel.setCapturedImage]) rather than reusing
/// `FoodRecognitionViewModel` - this is a plain display screen, not a
/// recognition flow, and doesn't need that ViewModel's capture-specific
/// state.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class LandmarkDetailView extends StatefulWidget {
  const LandmarkDetailView({super.key});

  @override
  State<LandmarkDetailView> createState() => _LandmarkDetailViewState();
}

class _LandmarkDetailViewState extends State<LandmarkDetailView> {
  late final LandmarkDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LandmarkDetailViewModel();

    // Pick up the food (and its photo) handed over by whichever screen
    // pushed here - FoodRecognitionView's "View Details" action, or
    // AddLandmarkView's chevron - BEFORE onInit(). Same hand-off pattern as
    // AddLandmarkView itself.
    final LocalFood? food = LandmarkDraftHandoff().takeRecognizedFood();
    if (food != null) _viewModel.setRecognizedFood(food);
    final XFile? image = LandmarkDraftHandoff().takeCapturedImage();
    if (image != null) _viewModel.setCapturedImage(image);
    // Whether this detail screen was opened from the additional-food capture
    // flow ("View Details" on the "Add More Food" camera) - if so its confirm
    // returns the food to the existing form instead of pushing a new one.
    _viewModel.setReturnToFormAsAdditionalFood(
      LandmarkDraftHandoff().takeReturnToFormAsAdditionalFood(),
    );
    // Whether the food was judged to be Malaysian local food - when not, the
    // "Add New Landmark" action below is hidden (details still shown).
    _viewModel.setIsLocalFood(LandmarkDraftHandoff().takeIsLocalFood());
    _viewModel.setFitsCatalogueCategory(
      LandmarkDraftHandoff().takeFitsCatalogueCategory(),
    );
    // Gemini's suggested price range for the food, carried onto the
    // submitted LandmarkItem.
    _viewModel.setPriceRange(
      priceMin: LandmarkDraftHandoff().takePriceMin(),
      priceMax: LandmarkDraftHandoff().takePriceMax(),
    );
    // Dietary restrictions for the recognised food, carried onto the
    // `food_dietary_restriction` association table if it becomes a new
    // catalogue row.
    _viewModel.setDietaryRestrictions(
      LandmarkDraftHandoff().takeDietaryRestrictions(),
    );
    // The observed/typed VARIANT name (`Cendol Jagung` -> `Cendol`) - written
    // to `landmark_item.variant`; empty when it equals the dictionary dish.
    _viewModel.setVariant(LandmarkDraftHandoff().takeVariant());
    // The tourist's restrictions this food conflicts with - shown as a
    // warning on the card (adding is still allowed).
    _viewModel.setDietaryRestrictionConflicts(
      LandmarkDraftHandoff().takeDietaryConflicts(),
    );
    // Where the food was captured - the form this screen opens needs it as
    // the landmark's location (and as the 50 m reference for later captures).
    _viewModel.setCaptureLocation(LandmarkDraftHandoff().takeCaptureLocation());
    // The first food's capture spot (additional-food flow) - lets this
    // screen re-check the 50 m same-restaurant rule before offering to add
    // this food, so "View Details" can never bypass the capture-range block.
    _viewModel.setReferenceLocation(
      LandmarkDraftHandoff().takeReferenceLocation(),
    );

    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// "Add New Landmark" (primary flow) - the reminder must be acknowledged
  /// before the form opens (see [showAddLandmarkReminderDialog]). The
  /// additional-food return needs no reminder: that food goes back onto an
  /// already-open form.
  ///
  /// A saved draft of the SAME dish (variant included) at this spot is
  /// offered for continuing first: "Continue submission" reopens it
  /// pre-filled, "Start a new one" falls through to the fresh form.
  Future<void> _proceedToAddLandmark(LandmarkDetailViewModel viewModel) async {
    if (!viewModel.returnToFormAsAdditionalFood) {
      final bool acknowledged = await showAddLandmarkReminderDialog(context);
      if (!acknowledged || !mounted) return;
      final LandmarkDraft? draft = await viewModel.draftToContinue();
      if (!mounted) return;
      if (draft != null) {
        final bool continues = await showContinueDraftDialog(
          context,
          dishLabel: continueDraftDishLabel(draft),
          restaurantName: draft.restaurantName,
        );
        if (!mounted) return;
        if (continues) {
          viewModel.openDraft(draft);
          return;
        }
      }
    }
    viewModel.proceedToAddLandmark();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkDetailViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Recognised Food'),
        body: SafeArea(
          child: Consumer<LandmarkDetailViewModel>(
            builder:
                (
                  BuildContext context,
                  LandmarkDetailViewModel viewModel,
                  Widget? _,
                ) {
                  final LocalFood? food = viewModel.recognizedFood;
                  if (food == null) {
                    return const Center(child: Text('No food to show.'));
                  }

                  return ListView(
                    padding: AppSpacing.screenPadding,
                    children: <Widget>[
                      _SuccessBanner(
                        isLocalFood: viewModel.isLocalFood,
                        fitsCatalogueCategory: viewModel.fitsCatalogueCategory,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // The same "Recognised Food" card as `AddLandmarkView`'s,
                      // just always expanded (no collapse arrow) and without the
                      // Form-1 price footer.
                      RecognisedFoodCard(
                        food: food,
                        variant: viewModel.variant,
                        image: viewModel.capturedImage,
                        collapsible: false,
                        dietaryConflicts: viewModel.dietaryConflicts,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (viewModel.isLocalFood &&
                          viewModel.fitsCatalogueCategory) ...<Widget>[
                        if (viewModel.isCaptureOutOfRange) ...<Widget>[
                          // Captured more than 50 m from the first food (50 m
                          // same-restaurant rule): the details are still
                          // worth viewing, but this food must not join the
                          // landmark from here - the camera screen already
                          // blocks it, and this screen must not be a way
                          // around that. Capture it again on site.
                          Text(
                            viewModel.captureRangeBlockMessage!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                        ] else if (viewModel.isAddLandmarkBlockedByLocation &&
                            !viewModel
                                .returnToFormAsAdditionalFood) ...<Widget>[
                          // At sea / outside Malaysia (A9): the food can still
                          // be viewed, but it must not become a landmark.
                          Text(
                            viewModel.addLandmarkLocationBlockMessage!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                        ] else ...<Widget>[
                          Text(
                            viewModel.returnToFormAsAdditionalFood
                                ? '                 Add this food to the landmark?'
                                : 'Would you like to add this as a new landmark?',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _proceedToAddLandmark(viewModel),
                              child: Text(
                                viewModel.returnToFormAsAdditionalFood
                                    ? 'Add to Landmark'
                                    : 'Add New Landmark',
                              ),
                            ),
                          ),
                        ],
                      ] else if (!viewModel.isLocalFood) ...<Widget>[
                        // Not Malaysian local food - showing the info is the
                        // whole point of this screen, but it must never be
                        // offered as a landmark.
                        const Text(
                          "This doesn't appear to be Malaysian local food, "
                          'so it cannot be added as a landmark.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium,
                        ),
                      ] else ...<Widget>[
                        // Malaysian, but not a catalogue dish type (snack,
                        // package, canned drink) - a Malaysian product that
                        // must never be offered as a landmark.
                        const Text(
                          'This is a Malaysian product but it is a snack or '
                          'packaged item, so it cannot be added.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  );
                },
          ),
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({
    required this.isLocalFood,
    required this.fitsCatalogueCategory,
  });

  /// Whether the shown food is Malaysian local food - changes the banner
  /// from a green "recognised" success into a caution-coloured "not local"
  /// note.
  final bool isLocalFood;

  /// Whether the shown food fits a catalogue dish type - when false the
  /// banner becomes a "Malaysian product, not addable" caution.
  final bool fitsCatalogueCategory;

  bool get _isAddable => isLocalFood && fitsCatalogueCategory;

  @override
  Widget build(BuildContext context) {
    final Color accent = _isAddable ? AppColors.success : AppColors.warning;
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: _isAddable
            ? AppColors.successContainer
            : AppColors.bannerCautionBackground,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            _isAddable ? Icons.check_circle : Icons.info_outline,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _isAddable
                      ? 'Local Food Recognised successfully!'
                      : !isLocalFood
                      ? 'Food Detected - Not Malaysian Local Food'
                      : 'Malaysian Product Detected',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _isAddable
                      ? 'Please review the information below.'
                      : !isLocalFood
                      ? 'You can view the details, but it cannot be added as a landmark.'
                      : 'It is a snack or packaged item, so it cannot be added as a landmark.',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
