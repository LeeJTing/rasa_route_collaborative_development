import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/landmark_draft.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/add_landmark_view_model.dart';
import '../../view_models/food_recognition_view_model.dart'
    show LandmarkDraftHandoff;
import '../common_widgets/app_dialog.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/combine_draft_dialog.dart';
import '../common_widgets/operating_hours_editor.dart';
import '../common_widgets/recognised_food_card.dart';
import 'widgets/location_picker_field.dart';

/// Add a landmark screen (UC500 BF-8..28).
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class AddLandmarkView extends StatefulWidget {
  const AddLandmarkView({super.key});

  @override
  State<AddLandmarkView> createState() => _AddLandmarkViewState();
}

class _AddLandmarkViewState extends State<AddLandmarkView>
    with WidgetsBindingObserver {
  late final AddLandmarkViewModel _viewModel;

  // The restaurant name can be set two ways: typed by the tourist, or
  // auto-filled from a signboard capture (setExtractedRestaurantName). A
  // plain `initialValue`-based TextFormField only reads its value once and
  // ignores later Provider rebuilds, so it would miss the auto-fill. A
  // persistent controller, synced only while the field ISN'T focused, gets
  // both right without fighting the tourist's own typing.
  late final TextEditingController _restaurantNameController;
  final FocusNode _restaurantNameFocusNode = FocusNode();

  /// Optional contact/address fields - simple controllers, no auto-fill, so
  /// they only need a plain value read (no focus-guarded sync like the name).
  late final TextEditingController _phoneController;
  late final TextEditingController _websiteController;
  late final TextEditingController _addressController;

  /// Last signboard-extraction version applied to `_restaurantNameController`
  /// (see the force-sync in `build` - a fresh extraction must overwrite the
  /// tourist's typed name even while the field is focused).
  int _appliedRestaurantNameVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = AddLandmarkViewModel();

    // Data from the previous screen (the recognized food, its photo, and
    // where it was captured) arrives through the hand-off, since routes
    // carry no arguments and a ViewModel takes no constructor parameters.
    // Set it BEFORE onInit() so the form opens already populated.
    final LocalFood? food = LandmarkDraftHandoff().takeRecognizedFood();
    if (food != null) {
      _viewModel.setRecognizedFood(
        food,
        priceMin: LandmarkDraftHandoff().takePriceMin(),
        priceMax: LandmarkDraftHandoff().takePriceMax(),
        confidence: LandmarkDraftHandoff().takeConfidence(),
        dietaryRestrictions: LandmarkDraftHandoff().takeDietaryRestrictions(),
        dietaryConflicts: LandmarkDraftHandoff().takeDietaryConflicts(),
        variant: LandmarkDraftHandoff().takeVariant(),
        captureLocation: LandmarkDraftHandoff().takeCaptureLocation(),
      );
    }
    final XFile? foodImage = LandmarkDraftHandoff().takeCapturedImage();
    if (foodImage != null) _viewModel.setRecognizedFoodImage(foodImage);

    // Continuing a saved incomplete submission: the whole form snapshot
    // arrives the same way and is restored BEFORE the text controllers are
    // built, so the fields open populated.
    final LandmarkDraft? draft = LandmarkDraftHandoff().takeDraft();
    if (draft != null) _viewModel.restoreDraft(draft);

    _restaurantNameController = TextEditingController(
      text: _viewModel.restaurantName,
    );
    _phoneController = TextEditingController(text: _viewModel.restaurantPhone);
    _websiteController = TextEditingController(
      text: _viewModel.restaurantWebsite,
    );
    _addressController = TextEditingController(
      text: _viewModel.restaurantAddress,
    );
    _appliedRestaurantNameVersion = _viewModel.extractedRestaurantNameVersion;
    _viewModel.onInit();

    // A submission resumed in its ALREADY-CONFIRMED state checks once for
    // ANOTHER saved submission for the same restaurant: the Confirm button
    // never runs on a confirmed form, yet the two drafts must still be
    // combinable (the absorbed row goes on the next save - see
    // `AddLandmarkViewModel.mergeExistingDraft`).
    if (draft != null && _viewModel.restaurantConfirmed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _offerDraftCombine(_viewModel);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restaurantNameController.dispose();
    _restaurantNameFocusNode.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  /// The app is closing / going to the background while this form is open -
  /// the tourist may never come back to it, so what they entered is kept as
  /// an incomplete submission (24 hours). This is a best-effort background
  /// save: it never blocks, and a success is reported when they return (see
  /// the post-frame notice in [build]).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _viewModel.saveDraft(background: true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        break;
    }
  }

  /// The system back gesture/button. While a field is focused (the keyboard
  /// is up) the first press only lowers the keyboard: that is what a tourist
  /// expects on a text form, and it must not look like they tried to leave -
  /// a keyboard dismissal used to throw "Leave this form?" at them out of
  /// nowhere. Only a back press that is NOT dismissing the keyboard asks the
  /// leave question.
  void _handleSystemBack() {
    // Never interrupt a submission: the form must stay until it finishes
    // (or fails) - otherwise the tourist could leave mid-write.
    if (_viewModel.isSubmitting) return;
    final FocusScopeNode focusScope = FocusScope.of(context);
    if (focusScope.hasFocus) {
      focusScope.unfocus();
      return;
    }
    _confirmLeave();
  }

  /// The app bar's back arrow and the system back gesture on this form:
  /// save what has been entered as an incomplete submission (kept for
  /// 24 hours), or keep editing. Leaving without saving is never silent -
  /// the tourist chose it explicitly. A form with nothing on it (no food, no
  /// photo, no name) has nothing to keep, so it just closes.
  ///
  /// A form resumed from a saved submission has NO Discard here: that delete
  /// already lives on the Incomplete Submissions screen, and offering it
  /// again would be a second, hidden way to lose the form. Only a fresh form
  /// offers it.
  ///
  /// Uses the shared [AppDialog] frame, so this confirmation matches the
  /// "Before you start" reminder instead of the default `AlertDialog` whose
  /// right-aligned action row fought the app's full-width buttons.
  Future<void> _confirmLeave() async {
    if (!_viewModel.hasDraftContent) {
      AppNavigator.pop();
      return;
    }
    final bool resumed = _viewModel.hasSavedDraft;
    final _LeaveChoice? choice = await showDialog<_LeaveChoice>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.exit_to_app_rounded,
        title: 'Leave this form?',
        message: resumed
            ? 'You can save what you have entered back into this incomplete '
                  'submission - it stays on the Incomplete Submissions '
                  'screen, kept for 24 hours after its last save.'
            : 'You can save what you have entered as an incomplete '
                  'submission - it will be kept for 24 hours, and you can '
                  'continue it the next time you are at this restaurant. If '
                  "you discard it, it can't be recovered.",
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(_LeaveChoice.save),
            child: const Text('Save & leave'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LeaveChoice.keepEditing),
            child: const Text('Keep editing'),
          ),
          if (!resumed)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LeaveChoice.discard),
              child: const Text('Discard'),
            ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _LeaveChoice.keepEditing) {
      return;
    }

    if (choice == _LeaveChoice.save) {
      final bool saved = await _viewModel.saveDraft();
      if (!mounted) return;
      if (!saved) {
        // Keep the tourist on the form - leaving now would lose the entry.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save the incomplete submission. Check your '
              'connection and try again.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Incomplete submission saved. It will be kept for 24 hours.',
          ),
        ),
      );
    } else {
      await _viewModel.discardDraft();
      if (!mounted) return;
    }
    AppNavigator.pop();
  }

  Future<void> _submit(AddLandmarkViewModel viewModel) async {
    await viewModel.submitLandmark();
    if (!mounted) return;
    if (viewModel.submitError == null) {
      // A13 - when the place already exists on the map (same name within
      // ~100m) the dishes were added to that place instead of creating a new
      // landmark - `submitConfirmation` says so (and lists any that already
      // existed); otherwise show the default success message.
      final String message =
          viewModel.submitConfirmation ??
          'Your landmark has been submitted successfully.'; // M8
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Clamped so a long merged-outcome message can never overflow the
          // snackbar - the ViewModel already caps the dish list; this caps
          // total lines as a final guard.
          content: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis),
        ),
      );
      AppNavigator.resetTo(AppRoutes.mainShell);
    }
  }

  /// "Add More Food" (A12) - opens the camera and, when it comes back with a
  /// dish the form already holds (same dish, same variant), says so right
  /// away: `AddLandmarkViewModel.addAdditionalFood` rejects the duplicate,
  /// and without this the tourist would just land back on an unchanged form.
  ///
  /// The notice is raised from THIS handler, where the captured result comes
  /// back, and not from a rebuild: the form sits underneath the camera while
  /// it is open, and a flag read in a post-frame callback of `build` may
  /// never run again before then.
  Future<void> _addMoreFood(AddLandmarkViewModel viewModel) async {
    await viewModel.openAddMoreFood();
    if (!mounted) return;
    if (!viewModel.takeDuplicateFoodNotice()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This dish is already on the form. Update its entry instead of '
          'adding it again.',
        ),
      ),
    );
  }

  /// "Confirm" under the Restaurant Name. It checks the mandatory photo and
  /// the name (`AddLandmarkViewModel.confirmRestaurant` - its problem, if
  /// any, is shown right away), then offers to combine this form with
  /// another unfinished submission for the same restaurant.
  Future<void> _confirmRestaurant(AddLandmarkViewModel viewModel) async {
    final String? problem = viewModel.confirmRestaurant();
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    await _offerDraftCombine(viewModel);
  }

  /// Looks for ANOTHER saved submission for the same restaurant (same name,
  /// first-food spot within 100 m - never this form's own row) and lets the
  /// tourist decide whether the two are combined into one submission.
  ///
  /// Called by [Confirm] and, once, when a form resumes an ALREADY-CONFIRMED
  /// draft: no Confirm click happens there, yet two drafts of one restaurant
  /// must still be combinable.
  Future<void> _offerDraftCombine(AddLandmarkViewModel viewModel) async {
    final LandmarkDraft? saved = await viewModel.draftForRestaurantMerge();
    if (!mounted || saved == null) return;
    final bool combine = await showCombineDraftDialog(
      context,
      restaurantName: saved.restaurantName,
    );
    if (!mounted || !combine) return;
    final List<String> updated = viewModel.mergeExistingDraft(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_mergeNotice(updated))));
  }

  /// The merge outcome shown after combining: dishes that were already on
  /// this form and only gained the saved submission's blank details, else a
  /// plain acknowledgement.
  static String _mergeNotice(List<String> updated) {
    if (updated.isEmpty) return 'Combined with your saved submission.';
    if (updated.length == 1) {
      return '${updated.single} is already in that submission - its details '
          'were updated.';
    }
    return '${updated.join(', ')} are already in that submission - their '
        'details were updated.';
  }

  @override
  Widget build(BuildContext context) {
    // A background auto-save (the app moved to the background) reports
    // itself here, once the tourist is looking at the app again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_viewModel.takeAutoDraftSavedNotice()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Incomplete submission saved automatically. It will be kept for '
            '24 hours.',
          ),
        ),
      );
    });

    return ChangeNotifierProvider<AddLandmarkViewModel>.value(
      value: _viewModel,
      // The system back button cannot leave the form silently: the tourist
      // is asked to save an incomplete submission, discard it, or keep
      // editing - but only after the back press has done its first job, see
      // [_handleSystemBack].
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          _handleSystemBack();
        },
        child: Scaffold(
          appBar: AppTopBar(
            title: 'Add New Landmark',
            // The top bar's arrow is explicit "leave this screen", so it
            // asks straight away - unlike the system back, which lowers the
            // keyboard first (see [_handleSystemBack]).
            onBack: () {
              if (_viewModel.isSubmitting) return;
              _confirmLeave();
            },
          ),
          body: SafeArea(
            child: Consumer<AddLandmarkViewModel>(
              builder:
                  (
                    BuildContext context,
                    AddLandmarkViewModel viewModel,
                    Widget? _,
                  ) {
                    // A fresh signboard result must overwrite the tourist's
                    // typed name even while the field is focused (the field
                    // regains focus when the capture route pops back). Detect
                    // it via the ViewModel's extraction version and force-sync;
                    // otherwise fall back to the focus-guarded sync, so normal
                    // auto-fill shows up without fighting the tourist's typing.
                    if (_appliedRestaurantNameVersion !=
                        viewModel.extractedRestaurantNameVersion) {
                      _restaurantNameController.text = viewModel.restaurantName;
                      _appliedRestaurantNameVersion =
                          viewModel.extractedRestaurantNameVersion;
                    } else if (!_restaurantNameFocusNode.hasFocus &&
                        _restaurantNameController.text !=
                            viewModel.restaurantName) {
                      _restaurantNameController.text = viewModel.restaurantName;
                    }

                    return Column(
                      children: <Widget>[
                        Expanded(
                          child: ListView(
                            padding: AppSpacing.screenPadding,
                            children: <Widget>[
                              if (viewModel.recognizedFood != null) ...<Widget>[
                                const _SuccessBanner(),
                                const SizedBox(height: AppSpacing.lg),
                                _PrimaryFoodSection(
                                  food: viewModel.recognizedFood!,
                                  variant: viewModel.recognizedFoodVariant,
                                  image: viewModel.recognizedFoodImage,
                                  imageUrl: viewModel.recognizedFoodImageUrl,
                                  price: viewModel.primaryFoodPrice,
                                  priceWarning:
                                      viewModel.primaryFoodPriceWarning,
                                  suggestedRange:
                                      viewModel.primaryFoodSuggestedPriceText,
                                  dietaryConflicts:
                                      viewModel.primaryFoodDietaryConflicts,
                                  onPriceChanged: viewModel.setPrimaryFoodPrice,
                                ),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              _AdditionalFoodsSection(
                                entries: viewModel.additionalFoods,
                                onAddMore: () => _addMoreFood(viewModel),
                                onPriceChanged:
                                    viewModel.setAdditionalFoodPrice,
                                onRemove: viewModel.removeAdditionalFood,
                                priceWarningFor:
                                    viewModel.additionalFoodPriceWarning,
                                suggestedRangeFor:
                                    viewModel.additionalFoodSuggestedPriceText,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _ImageCaptureRow(
                                capturedImage: viewModel.capturedImage,
                                capturedImageUrl: viewModel.capturedImageUrl,
                                capturedImageType: viewModel.capturedImageType,
                                isSignboardDisabled:
                                    viewModel.isSignboardDisabled,
                                isStallDisabled: viewModel.isStallDisabled,
                                onCaptureSignboard:
                                    viewModel.openSignboardCapture,
                                onCaptureStall: viewModel.openStallCapture,
                                onCancelImage: viewModel.clearCapturedImage,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _RestaurantNameField(
                                controller: _restaurantNameController,
                                focusNode: _restaurantNameFocusNode,
                                maxLength: viewModel.restaurantNameMaxLength,
                                error: viewModel.restaurantName.isEmpty
                                    ? null
                                    : viewModel.restaurantNameError,
                                warning: viewModel.restaurantNameWarning,
                                onChanged: viewModel.setRestaurantName,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _ConfirmRestaurantRow(
                                confirmed: viewModel.restaurantConfirmed,
                                onConfirm: () => _confirmRestaurant(viewModel),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _ContactDetailsSection(
                                phoneController: _phoneController,
                                websiteController: _websiteController,
                                phoneMaxLength: viewModel.phoneMaxLength,
                                websiteMaxLength: viewModel.websiteMaxLength,
                                phoneError: viewModel.restaurantPhoneError,
                                websiteError: viewModel.restaurantWebsiteError,
                                websiteWarning:
                                    viewModel.restaurantWebsiteWarning,
                                websiteStatus: viewModel.websiteLinkStatus,
                                websiteStatusIsWarning:
                                    viewModel.websiteLinkUnreachable,
                                onPhoneChanged: viewModel.setRestaurantPhone,
                                onWebsiteChanged:
                                    viewModel.setRestaurantWebsite,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _RestaurantAddressSection(
                                controller: _addressController,
                                maxLength: viewModel.addressMaxLength,
                                error: viewModel.restaurantAddressError,
                                warning: viewModel.restaurantAddressWarning,
                                onChanged: viewModel.setRestaurantAddress,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              const Text(
                                'Location (GPS)',
                                style: AppTextStyles.titleSmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              if (viewModel.addLocationBlockMessage !=
                                  null) ...<Widget>[
                                _LocationBlockedNotice(
                                  message: viewModel.addLocationBlockMessage!,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              LocationPickerField(
                                center: viewModel.baseLocation,
                                pin: viewModel.adjustedLocation.isKnown
                                    ? viewModel.adjustedLocation
                                    : viewModel.baseLocation,
                                errorMessage: viewModel.locationError,
                                onMove: viewModel.adjustLandmarkLocation,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              OperatingHoursEditor(
                                operatingHours: viewModel.operatingHours,
                                onStatusChanged: viewModel.setDayStatus,
                                onRangeTimeChanged: viewModel.setRangeTime,
                                onAddRange: viewModel.addTimeRange,
                                onRemoveRange: viewModel.removeTimeRange,
                                onCopyMondayToAll:
                                    viewModel.copyMondayToAllWeekdays,
                              ),
                              if (viewModel.submitError != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  viewModel.submitError!,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xxl),
                            ],
                          ),
                        ),
                        _BottomActions(
                          canSubmit:
                              viewModel.canSubmit && !viewModel.isSubmitting,
                          isSubmitting: viewModel.isSubmitting,
                          reason: viewModel.canSubmit
                              ? null
                              : viewModel.canSubmitReason,
                          onSubmit: () => _submit(viewModel),
                        ),
                      ],
                    );
                  },
            ),
          ),
        ),
      ),
    );
  }
}

/// What the tourist chose when leaving the form - see [_confirmLeave].
enum _LeaveChoice { keepEditing, save, discard }

/// Shown on the Location section when the current fix is at sea / outside
/// Malaysia (A9): a hard notice that no landmark can be submitted from here.
class _LocationBlockedNotice extends StatelessWidget {
  const _LocationBlockedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: const BoxDecoration(
        color: AppColors.bannerCautionBackground,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.location_off,
            size: 18,
            color: AppColors.bannerCautionText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.bannerCautionText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Food recognised successfully!" banner (Figma "Form 1" - Green Notif),
/// matching `RecognisedFoodDetailsView`'s `_SuccessBanner` but with this
/// screen's own copy. Not shared between the two files (no new shared-widget
/// file per the project's "don't add new files" convention) - if a third
/// screen needs the same banner, that's the point to promote one.
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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.check_circle, color: AppColors.success),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Food recognised successfully!',
                  style: AppTextStyles.titleSmall,
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
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

/// Recognised food card + its price input (A16). Matches the Figma "Form 1"
/// layout: the shared [RecognisedFoodCard] (thumbnail on the left,
/// Dish/Variant/Origin/Food Category/Meal Type on the right, expandable to
/// Taste/Description/Cooking Style/Cultural Background) with the price field
/// as its footer. Same card as `LandmarkDetailView` shows - just with the
/// collapse arrow and the price footer that Form 1 needs.
class _PrimaryFoodSection extends StatelessWidget {
  const _PrimaryFoodSection({
    required this.food,
    this.variant = '',
    required this.image,
    required this.price,
    required this.onPriceChanged,
    this.imageUrl,
    this.priceWarning,
    this.suggestedRange,
    this.dietaryConflicts = const <String>[],
  });

  final LocalFood food;

  /// The observed/typed VARIANT name when it EXTENDS the dictionary dish
  /// into an unlisted variant (`Cendol Jagung` -> `Cendol`) - shown on the
  /// shared card; empty when the name IS the dish.
  final String variant;
  final XFile? image;

  /// Stored URL of the food's photo (a resumed draft) - used when [image] is
  /// null.
  final String? imageUrl;
  final double? price;
  final ValueChanged<double> onPriceChanged;

  /// Optional soft price guidance (Gemini's suggested range) under the field.
  final String? priceWarning;

  /// Gemini's suggested price range as an informational line - see
  /// `_PriceField.suggestedRange`.
  final String? suggestedRange;

  /// Restrictions this dish conflicts with - see `RecognisedFoodCard`.
  final List<String> dietaryConflicts;

  @override
  Widget build(BuildContext context) {
    return RecognisedFoodCard(
      food: food,
      variant: variant,
      image: image,
      imageUrl: imageUrl,
      collapsible: true,
      dietaryConflicts: dietaryConflicts,
      footer: _PriceField(
        label: 'Price (MYR)',
        initialValue: price,
        warning: priceWarning,
        suggestedRange: suggestedRange,
        onChanged: onPriceChanged,
      ),
    );
  }
}

/// A single price entry field. STRICTLY capped + formatted so a pasted blob
/// can never overflow: max 7 characters, digits and one dot only, at most 4
/// integer digits and 2 decimals (the 0.01-1000 MYR rule). Shows a precise
/// inline error under the field when the value is unparsable or outside the
/// allowed range.
///
/// [suggestedRange] (Gemini's suggested range as a display line) is shown
/// whenever it is known - INCLUDING while the value is invalid, so the
/// tourist can see the expected range while fixing the number. The stronger
/// amber [warning] (a valid price outside the range) replaces it only while
/// there is no error.
class _PriceField extends StatefulWidget {
  const _PriceField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.warning,
    this.suggestedRange,
  });

  final String label;
  final double? initialValue;
  final ValueChanged<double> onChanged;

  /// Optional soft price guidance (Gemini's suggested range) shown under the
  /// field - a warning, not an error.
  final String? warning;

  /// Gemini's suggested price range as an informational line ("Suggested
  /// price: RM 2.00 - RM 8.00") - always shown when known (see class doc).
  final String? suggestedRange;

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  /// '1000.00' is the widest allowed value (0.01-1000 MYR, 2 decimals).
  static const int _maxLength = 7;

  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final String value = raw.trim();
    String? error;
    double? parsed;
    if (value.isNotEmpty) {
      final bool wellFormed = RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(value);
      parsed = wellFormed ? double.tryParse(value) : null;
      if (parsed == null) {
        error = 'Use numbers only, up to 2 decimals (e.g. 12.50).';
      } else if (parsed <= 0 || parsed > 1000) {
        error = 'Price must be between 0.01 and 1000 MYR.';
      }
    }
    if (error != _error) setState(() => _error = error);
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          maxLength: _maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          inputFormatters: <TextInputFormatter>[
            const _DecimalInputFormatter(
              maxIntegralDigits: 4,
              maxFractionDigits: 2,
            ),
          ],
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixText: 'RM ',
            counterText: '',
            errorText: _error,
            errorMaxLines: 2,
          ),
        ),
        if (widget.warning != null && _error == null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.warning!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
          ),
        ] else if (widget.suggestedRange != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.suggestedRange!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Keeps a decimal price well-formed while typing: at most
/// [maxIntegralDigits] digits before the dot, at most [maxFractionDigits]
/// after it, and never more than one dot.
class _DecimalInputFormatter extends TextInputFormatter {
  const _DecimalInputFormatter({
    required this.maxIntegralDigits,
    required this.maxFractionDigits,
  });

  final int maxIntegralDigits;
  final int maxFractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text = newValue.text;
    if (text.isEmpty) return newValue;
    final RegExp pattern = RegExp(
      '^(\\d{0,$maxIntegralDigits})(\\.(\\d{0,$maxFractionDigits})?)?\$',
    );
    return pattern.hasMatch(text) ? newValue : oldValue;
  }
}

/// Restaurant Name field - a bordered info row (icon + name), matching the
/// Figma "Form 1" container style, rather than a bare `TextFormField`.
/// Directly editable throughout (no separate Edit-toggle interaction) - it's
/// auto-filled when a signboard capture succeeds (see
/// `_AddLandmarkViewState`'s persistent controller for why a plain
/// `initialValue` field wouldn't pick that up), or typed directly otherwise.
class _RestaurantNameField extends StatelessWidget {
  const _RestaurantNameField({
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.error,
    this.warning,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;

  /// Inline error shown under the field (null when the name is fine). The
  /// "required" error is deliberately NOT shown inline while the field is
  /// empty - the submit bar's reason covers that without nagging.
  final String? error;

  /// Amber warning shown while the name is in the 31-40 warn zone - typing
  /// is allowed up to [maxLength] but submission is blocked by the VM.
  final String? warning;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Restaurant Name', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: error != null
                  ? AppColors.error
                  : (warning != null ? AppColors.warning : AppColors.outline),
            ),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.storefront_outlined,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLength: maxLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.deny(
                      RegExp(r'[\x00-\x1F\x7F]'),
                    ),
                  ],
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    counterText: '',
                    hintText: 'Enter restaurant name',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        if (error == null && warning != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            warning!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}

/// A labelled, icon-bordered text input reused by the optional contact and
/// address fields - visually consistent with `_RestaurantNameField`. Enforces
/// [maxLength] while typing (counter hidden) and blocks control characters /
/// newlines from pasted input; field-level [error] text renders below.
class _FormTextField extends StatelessWidget {
  const _FormTextField({
    required this.label,
    required this.icon,
    required this.hint,
    required this.controller,
    required this.maxLength,
    required this.onChanged,
    required this.error,
    this.warning,
    this.status,
    this.statusColor = AppColors.textSecondary,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
  });

  final String label;
  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String> onChanged;
  final String? error;

  /// Amber warning shown while the value is in its warn zone (e.g. website
  /// 76-79 chars) - typing continues to [maxLength] but submission is
  /// blocked by the ViewModel.
  final String? warning;

  /// Neutral helper line under the field (e.g. the website link probe's
  /// "Checking this link…"); [statusColor] carries the tone.
  final String? status;
  final Color statusColor;
  final TextInputType keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: error != null
                  ? AppColors.error
                  : (warning != null ? AppColors.warning : AppColors.outline),
            ),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: <TextInputFormatter>[
                    // Blocks newlines and all control bytes from pasted text.
                    FilteringTextInputFormatter.deny(
                      RegExp(r'[\x00-\x1F\x7F]'),
                    ),
                  ],
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    counterText: '',
                    hintText: hint,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        if (error == null && warning != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            warning!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
          ),
        ],
        if (error == null && status != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            status!,
            style: AppTextStyles.bodySmall.copyWith(color: statusColor),
          ),
        ],
      ],
    );
  }
}

/// The "Confirm" action under the Restaurant Name - submission is gated on
/// it (see `AddLandmarkViewModel.confirmRestaurant`): it states the
/// signboard/stall photo and the name are in place, and it is the moment
/// another unfinished submission for the same restaurant is looked up so the
/// two can be combined. Once confirmed the row reports the state instead of
/// offering the button again.
class _ConfirmRestaurantRow extends StatelessWidget {
  const _ConfirmRestaurantRow({
    required this.confirmed,
    required this.onConfirm,
  });

  final bool confirmed;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (confirmed) {
      return Row(
        children: <Widget>[
          const Icon(
            Icons.check_circle,
            size: AppSizes.inlineNoticeIconSize,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Restaurant name confirmed',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onConfirm,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Confirm'),
      ),
    );
  }
}

/// Optional phone + website fields under the restaurant name. Both optional;
/// when the tourist types anything the ViewModel validates it (Malaysian
/// phone format; strict http(s) URL format - RFC 3986 characters, no spaces,
/// real dotted domain, exactly one link). The website is also probed live
/// while typing ("Checking this link…", then a note when it cannot be
/// opened) and re-checked - blocking - at submit.
class _ContactDetailsSection extends StatelessWidget {
  const _ContactDetailsSection({
    required this.phoneController,
    required this.websiteController,
    required this.phoneMaxLength,
    required this.websiteMaxLength,
    required this.phoneError,
    required this.websiteError,
    required this.websiteWarning,
    required this.websiteStatus,
    required this.websiteStatusIsWarning,
    required this.onPhoneChanged,
    required this.onWebsiteChanged,
  });

  final TextEditingController phoneController;
  final TextEditingController websiteController;
  final int phoneMaxLength;
  final int websiteMaxLength;
  final String? phoneError;
  final String? websiteError;

  /// Amber warning while the website is near its 2048 cap (2043+).
  final String? websiteWarning;

  /// Live link-probe status ("Checking this link…" / "could not open").
  /// [websiteStatusIsWarning] colours the un-opened note amber instead of
  /// the neutral helper tone.
  final String? websiteStatus;
  final bool websiteStatusIsWarning;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onWebsiteChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('Contact Details (Optional)', style: AppTextStyles.titleSmall),
      const SizedBox(height: AppSpacing.sm),
      _FormTextField(
        label: 'Phone Number',
        icon: Icons.phone_outlined,
        hint: '+60 12-345 6789',
        controller: phoneController,
        maxLength: phoneMaxLength,
        keyboardType: TextInputType.phone,
        onChanged: onPhoneChanged,
        error: phoneError,
      ),
      const SizedBox(height: AppSpacing.sm),
      _FormTextField(
        label: 'Website',
        icon: Icons.language_outlined,
        hint: 'https://example.com',
        controller: websiteController,
        maxLength: websiteMaxLength,
        keyboardType: TextInputType.url,
        onChanged: onWebsiteChanged,
        error: websiteError,
        warning: websiteWarning,
        status: websiteStatus,
        statusColor: websiteStatusIsWarning
            ? AppColors.warning
            : AppColors.textSecondary,
      ),
    ],
  );
}

/// Optional restaurant address field. When the tourist types anything it must
/// be at least 5 characters, use only letters/digits/spaces/common address
/// punctuation, and respect [maxLength].
class _RestaurantAddressSection extends StatelessWidget {
  const _RestaurantAddressSection({
    required this.controller,
    required this.maxLength,
    required this.error,
    this.warning,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int maxLength;
  final String? error;

  /// Amber warning while the address is close to its cap (see ViewModel).
  final String? warning;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => _FormTextField(
    label: 'Restaurant Address (Optional)',
    icon: Icons.place_outlined,
    hint: 'e.g. 12, Jalan Bukit Bintang, Kuala Lumpur',
    controller: controller,
    maxLength: maxLength,
    maxLines: 2,
    onChanged: onChanged,
    error: error,
    warning: warning,
  );
}

/// The two mandatory-one-of-two capture buttons (BF-16, A17), before a photo
/// exists. Whichever is used disables the other -
/// `isSignboardDisabled`/`isStallDisabled` come straight from the ViewModel.
/// Once [capturedImage] is set, shows that photo with two controls instead:
/// a "Retake" link (re-opens the SAME capture mode that was used - the other
/// stays disabled throughout, per BF-16/A17's "exactly one of two" rule) and
/// an "x" (cancels the image entirely, re-enabling both capture buttons -
/// undoes the choice rather than just replacing the photo).
class _ImageCaptureRow extends StatelessWidget {
  const _ImageCaptureRow({
    required this.capturedImage,
    required this.capturedImageType,
    required this.isSignboardDisabled,
    required this.isStallDisabled,
    required this.onCaptureSignboard,
    required this.onCaptureStall,
    required this.onCancelImage,
    this.capturedImageUrl,
  });

  final XFile? capturedImage;

  /// Stored URL of the signboard/stall photo (a resumed draft) - used when
  /// [capturedImage] is null.
  final String? capturedImageUrl;
  final String? capturedImageType;
  final bool isSignboardDisabled;
  final bool isStallDisabled;
  final VoidCallback onCaptureSignboard;
  final VoidCallback onCaptureStall;
  final VoidCallback onCancelImage;

  @override
  Widget build(BuildContext context) {
    final XFile? image = capturedImage;
    final String? storedUrl = capturedImageUrl;
    if (image != null || storedUrl != null) {
      final bool isSignboard = capturedImageType == 'signboard';
      final VoidCallback retake = isSignboard
          ? onCaptureSignboard
          : onCaptureStall;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isSignboard ? 'Signboard Image' : 'Stall Image',
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.cardRadius,
            child: Stack(
              children: <Widget>[
                if (image != null)
                  FutureBuilder<Uint8List>(
                    future: image.readAsBytes(),
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<Uint8List> snapshot,
                        ) {
                          if (!snapshot.hasData) {
                            return const SizedBox(
                              width: double.infinity,
                              height: AppSizes.capturedPhotoPreviewHeight,
                              child: ColoredBox(
                                color: AppColors.surfaceVariant,
                              ),
                            );
                          }
                          return Image.memory(
                            snapshot.data!,
                            width: double.infinity,
                            height: AppSizes.capturedPhotoPreviewHeight,
                            fit: BoxFit.cover,
                          );
                        },
                  )
                else
                  Image.network(
                    storedUrl!,
                    width: double.infinity,
                    height: AppSizes.capturedPhotoPreviewHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: double.infinity,
                      height: AppSizes.capturedPhotoPreviewHeight,
                      child: ColoredBox(color: AppColors.surfaceVariant),
                    ),
                  ),
                Positioned(
                  top: AppSpacing.xs,
                  left: AppSpacing.xs,
                  child: InkWell(
                    onTap: onCancelImage,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: const BoxDecoration(
                        color: AppColors.scrim,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.onPrimary,
                        size: AppSizes.addRangeIconSize,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: TextButton(
                    onPressed: retake,
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.scrim,
                    ),
                    child: Text(
                      'Retake',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Restaurant Photo', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Capture either the signboard or the stall - whichever this landmark has.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isSignboardDisabled ? null : onCaptureSignboard,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Capture Signboard'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isStallDisabled ? null : onCaptureStall,
                icon: const Icon(Icons.storefront),
                label: const Text('Capture Stall Image'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Additional foods list + "Add More Food" (A12), each with its own price.
class _AdditionalFoodsSection extends StatelessWidget {
  const _AdditionalFoodsSection({
    required this.entries,
    required this.onAddMore,
    required this.onPriceChanged,
    required this.onRemove,
    required this.priceWarningFor,
    required this.suggestedRangeFor,
  });

  final List<LandmarkFoodEntry> entries;
  final VoidCallback onAddMore;
  final void Function(int entryId, double price) onPriceChanged;
  final ValueChanged<int> onRemove;

  /// Returns the soft price guidance for one entry (Gemini's suggested range).
  final String? Function(int entryId) priceWarningFor;

  /// Returns the suggested-range display line for one entry - see
  /// `_PriceField.suggestedRange`.
  final String? Function(int entryId) suggestedRangeFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Additional Foods (Optional)',
          style: AppTextStyles.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final LandmarkFoodEntry entry in entries)
          Padding(
            key: ValueKey<int>(entry.entryId),
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            // Same shared card as the primary food - thumbnail on the left,
            // dish/variant/origin/food category/meal type on the right,
            // collapsible down to taste/description etc. - with the price
            // field and a remove button as its footer.
            child: RecognisedFoodCard(
              food: entry.food,
              variant: entry.variant,
              image: entry.image,
              imageUrl: entry.photoRef?.url,
              collapsible: true,
              footer: Row(
                children: <Widget>[
                  Expanded(
                    child: _PriceField(
                      label: 'Price',
                      initialValue: entry.price,
                      warning: priceWarningFor(entry.entryId),
                      suggestedRange: suggestedRangeFor(entry.entryId),
                      onChanged: (double price) =>
                          onPriceChanged(entry.entryId, price),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => onRemove(entry.entryId),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onAddMore,
          icon: const Icon(Icons.add),
          label: const Text('Add More Food'),
        ),
      ],
    );
  }
}

/// Bottom Submit bar, pinned below the scrolling form.
class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
    this.reason,
  });

  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  /// Why the button is disabled, shown above it (null = ready to submit).
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.screenPadding,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (reason != null) ...<Widget>[
              Text(
                reason!,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? onSubmit : null,
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
