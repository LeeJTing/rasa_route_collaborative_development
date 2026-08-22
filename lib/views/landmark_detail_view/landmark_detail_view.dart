import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/food_recognition_view_model.dart'
    show LandmarkDraftHandoff;
import '../../view_models/landmark_detail_view_model.dart';
import '../common_widgets/app_top_bar.dart';
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

    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
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
                      const _SuccessBanner(),
                      const SizedBox(height: AppSpacing.lg),
                      // The same "Recognised Food" card as `AddLandmarkView`'s,
                      // just always expanded (no collapse arrow) and without the
                      // Form-1 price footer.
                      RecognisedFoodCard(
                        food: food,
                        image: viewModel.capturedImage,
                        collapsible: false,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        viewModel.returnToFormAsAdditionalFood
                            ? 'Add this food to the landmark?'
                            : 'Would you like to add this as a new landmark?',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: viewModel.proceedToAddLandmark,
                          child: Text(
                            viewModel.returnToFormAsAdditionalFood
                                ? 'Add to Landmark'
                                : 'Add New Landmark',
                          ),
                        ),
                      ),
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
  const _SuccessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: const BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.check_circle, color: AppColors.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Local Food Recognised successfully!',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Please review the information below.',
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
