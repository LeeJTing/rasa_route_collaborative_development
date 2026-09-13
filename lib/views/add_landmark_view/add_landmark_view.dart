import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/address_suggestion.dart';
import '../../domain_model/landmark_draft.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/place_overwrite_report.dart';
import '../../domain_model/similar_place_candidate.dart';
import '../../view_models/add_landmark_view_model.dart';
import '../../view_models/food_recognition_view_model.dart'
    show LandmarkDraftHandoff;
import '../common_widgets/app_dialog.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/combine_draft_dialog.dart';
import '../common_widgets/enlarged_image_dialog.dart';
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

  /// Optional contact fields are plain controllers; the address one is ALSO
  /// filled from the map, so it gets a focus node and a version-sync like
  /// the restaurant name (see [_appliedAddressVersion]).
  late final TextEditingController _phoneController;
  late final TextEditingController _websiteController;
  late final TextEditingController _addressController;
  final FocusNode _addressFocusNode = FocusNode();

  /// Last signboard-extraction version applied to `_restaurantNameController`
  /// (see the force-sync in `build` - a fresh extraction must overwrite the
  /// tourist's typed name even while the field is focused).
  int _appliedRestaurantNameVersion = 0;

  /// Last address version applied to `_addressController` (see
  /// `AddLandmarkViewModel.addressVersion` - the map, a picked suggestion or
  /// the "use the map pin's address" button bumps it, and the field must
  /// show the new text even while focused).
  int _appliedAddressVersion = 0;

  /// True from the moment Submit is tapped until the whole flow - the
  /// overwrite pre-flight, the submission and its outcome - has finished.
  /// It disables the button while the pre-flight network check runs and
  /// keeps a second tap from stacking a parallel flow on top of it (user
  /// report, 2026-09-14: a tap could sit with no visible reaction and
  /// invite another).
  bool _submitFlowActive = false;

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
    _phoneController = TextEditingController(
      text: _viewModel.restaurantPhoneLocal,
    );
    _websiteController = TextEditingController(
      text: _viewModel.restaurantWebsite,
    );
    _addressController = TextEditingController(
      text: _viewModel.restaurantAddress,
    );
    _appliedRestaurantNameVersion = _viewModel.extractedRestaurantNameVersion;
    _viewModel.onInit();

    // Fill an empty address from the pinned (captured) spot once the first
    // frame is up - the ViewModel only talks to the geocoder while a screen
    // is watching it. A restored draft's address, or anything typed, is
    // never overwritten.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewModel.prefillAddressFromMap();
    });

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
    _addressFocusNode.dispose();
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
        await _showNotice(
          icon: Icons.error_outline,
          title: 'Save failed',
          message:
              'Could not save the incomplete submission. Check your '
              'connection and try again.',
        );
        return;
      }
      // No "saved" snackbar: the leave dialog already said exactly that
      // ("it stays on the Incomplete Submissions screen, kept for 24 hours
      // after its last save"), and the tourist has just read it - a second
      // announcement of the same thing only adds noise (user request).
    } else {
      await _viewModel.discardDraft();
      if (!mounted) return;
    }
    AppNavigator.pop();
  }

  /// Submits the form with the blocking "submitting" page (see
  /// [_SubmittingPage]) over it for as long as the write is in flight, so
  /// nothing on the form can be edited (or left) mid-write.
  ///
  /// The page goes up only once `submitLandmark` has actually STARTED: its
  /// own checks run synchronously before its first await, so a form it
  /// rejects shows that message with no spinner flashing over it. A FAILED
  /// submit takes the page down and leaves the tourist on the very same,
  /// editable form with the reason under the Submit bar - ready to fix - and
  /// a successful one hands them back to the dashboard.
  Future<void> _submit(AddLandmarkViewModel viewModel) async {
    // One flow at a time: the pre-flight question below is a network check,
    // and a tap while it runs must not stack a parallel flow. The flag also
    // keeps the button disabled until the whole flow - question, submission,
    // outcome - is done, so the tap visibly takes hold right away (user
    // report, 2026-09-14: it could sit with no reaction and invite another
    // tap).
    if (_submitFlowActive) return;
    setState(() => _submitFlowActive = true);
    try {
      await _runSubmitFlow(viewModel);
    } finally {
      // The form may already be gone (a successful submit resets to the
      // shell) - only touch state while it is still on screen.
      if (mounted) setState(() => _submitFlowActive = false);
    }
  }

  /// The submit flow proper (see [_submit], which guards and brackets it):
  /// asks the pre-flight question, runs the submission behind the blocking
  /// page, and lands on the dashboard when it succeeds.
  Future<void> _runSubmitFlow(AddLandmarkViewModel viewModel) async {
    // Ask about replacing the same-place record's stored details BEFORE the
    // write starts - this is the last moment the tourist can keep them.
    await _askDetailsOverwriteIfNeeded(viewModel);
    if (!mounted) return;
    final Future<void> submission = viewModel.submitLandmark();
    final bool started = viewModel.isSubmitting;
    if (started) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => const _BlockingPage(
            title: 'Submitting your landmark…',
            message:
                'This can take a moment - your photos are being uploaded. '
                "Please keep this screen open; we'll take you back to the "
                'dashboard once it is done.',
          ),
        ),
      );
    }

    await submission;
    if (!mounted) return;
    // The page comes down exactly once, on every outcome.
    if (started) Navigator.of(context, rootNavigator: true).pop();
    if (viewModel.submitError != null) return; // Fix it on this form.

    // A13 - when the place already exists on the map (same name within
    // ~100m) the dishes were added to that place instead of creating a new
    // landmark - `submitConfirmation` says so (and lists any that already
    // existed); otherwise show the default success message.
    final String message =
        viewModel.submitConfirmation ??
        'Your landmark has been submitted successfully.'; // M8
    // An ACKNOWLEDGEMENT, not a snackbar: the same modal frame every other
    // notice in this flow uses (`AppDialog`), so the outcome is read and
    // dismissed deliberately instead of sliding away while the screen
    // changes under it (user request - consistent with the form's dialogs).
    // The dashboard navigation happens AFTER it, so the tourist sees the
    // outcome on the form they submitted.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.check_circle_outline,
        title: 'Landmark submitted',
        message: message,
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Done with the form: the tourist lands on the dashboard (the shell's
    // first tab), not back on a form that would only be re-submitted.
    AppNavigator.resetTo(AppRoutes.mainShell);
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
    await _showNotice(
      icon: Icons.restaurant_menu,
      title: 'Already on this form',
      message: viewModel.duplicateFoodNotice,
    );
  }

  /// "Confirm" under the Restaurant Name. It checks the mandatory photo and
  /// the name (`AddLandmarkViewModel.confirmRestaurant` - its problem, if
  /// any, is shown right away), re-checks a name the tourist EDITED against
  /// the signboard photo (see [_showNameMismatchNotice]), asks about a nearby
  /// place whose stored photo looks like this one (see [_askSimilarPlace]),
  /// then offers to combine this form with another unfinished submission for
  /// the same restaurant.
  ///
  /// The checks are Gemini calls, so the click can take a moment: the form is
  /// BLOCKED behind [_BlockingPage] while they run (nothing may change the
  /// name or the photos mid-question), and the Confirm row reports progress.
  Future<void> _confirmRestaurant(AddLandmarkViewModel viewModel) async {
    // A photo + a name means the checks will actually run - show the wait
    // only then, so a form that is rejected outright never flashes it.
    final bool wait =
        viewModel.hasImageCaptured &&
        viewModel.restaurantName.trim().isNotEmpty;
    final Future<String?> confirming = viewModel.confirmRestaurant();
    if (wait) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => const _BlockingPage(
            title: 'Checking nearby restaurants…',
            message:
                'We are comparing your photo with the places already saved '
                'around here. Please keep this screen open - the form cannot '
                'be edited until this finishes.',
          ),
        ),
      );
    }
    final String? problem = await confirming;
    if (!mounted) return;
    if (wait) Navigator.of(context, rootNavigator: true).pop();
    if (problem != null) {
      await _showNotice(
        icon: Icons.info_outline,
        title: 'Cannot confirm yet',
        message: problem,
      );
      return;
    }
    if (viewModel.takeSignboardNameMismatch()) {
      await _showNameMismatchNotice(viewModel);
      return;
    }
    if (viewModel.similarPlacePrompt != null) {
      await _askSimilarPlace(viewModel);
      return;
    }
    await _askDetailsOverwriteIfNeeded(viewModel);
    if (!mounted) return;
    await _offerDraftCombine(viewModel);
  }

  /// Asks whether this submission REPLACES details the same-place record
  /// already stores (phone, website, address, the pin, a day's hours) - the
  /// merge would otherwise overwrite them silently. Does nothing when there
  /// is nothing to ask, and the answer is remembered for the submit that
  /// follows.
  Future<void> _askDetailsOverwriteIfNeeded(
    AddLandmarkViewModel viewModel,
  ) async {
    if (!await viewModel.checkDetailsOverwrite()) return;
    if (!mounted) return;
    final PlaceOverwriteReport? report = viewModel.overwritePrompt;
    if (report == null) return;
    final bool? overwrite = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.edit_note_outlined,
        title: 'Replace the existing details?',
        message:
            '"${report.name}" already has ${report.fieldsText}. Replace it '
            'with the details you entered?',
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replace them'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep the existing details'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // A dismissed dialog keeps the stored record - the safe direction.
    viewModel.resolveOverwrite(overwrite == true);
  }

  /// "Is this the same restaurant?" - a nearby place, saved under a name that
  /// only LOOKS like this form's, whose stored photo Gemini judged to be the
  /// same restaurant. The question shows that place's OWN photo (the user's
  /// request: the similar result's signboard is the evidence), its name and
  /// how far away it is.
  ///
  /// "Yes" adopts that place's name and reports which of this form's dishes
  /// it already lists (see [_acknowledgeExistingDishes]); "No" keeps this
  /// form as its own new landmark.
  Future<void> _askSimilarPlace(AddLandmarkViewModel viewModel) async {
    final SimilarPlaceCandidate? candidate = viewModel.similarPlacePrompt;
    if (candidate == null) return;
    final String? photoUrl = candidate.imageUrl;
    final bool? samePlace = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.storefront_outlined,
        title: 'Is this the same restaurant?',
        message:
            'A place saved nearby looks like your photo: "${candidate.name}" '
            '(${_shortDistance(candidate.distanceMetres)} away).',
        extra: photoUrl == null
            ? null
            : ClipRRect(
                borderRadius: AppRadius.cardRadius,
                child: Image.network(
                  photoUrl,
                  height: AppSizes.capturedPhotoPreviewHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: AppSizes.capturedPhotoPreviewHeight,
                    child: ColoredBox(color: AppColors.surfaceVariant),
                  ),
                ),
              ),
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, this is the place'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No, a different place'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (samePlace != true) {
      viewModel.rejectSimilarPlace();
      if (!mounted) return;
      await _askDetailsOverwriteIfNeeded(viewModel);
      if (!mounted) return;
      await _offerDraftCombine(viewModel);
      return;
    }

    await viewModel.acceptSimilarPlace();
    if (!mounted) return;
    await _acknowledgeExistingDishes(viewModel, candidate.name);
  }

  /// The acknowledgement after "yes, that is the place": which of this form's
  /// dishes it ALREADY lists. One [OK], no way back (the user's choice) - the
  /// tourist sees what it means before anything changes.
  ///
  /// Every dish already there -> nothing would be written: the form is left
  /// for the dashboard (the incomplete submission goes with it).
  /// Only some -> those dishes are dropped from THIS submission (the place
  /// keeps its own rows) and the form carries on.
  Future<void> _acknowledgeExistingDishes(
    AddLandmarkViewModel viewModel,
    String placeName,
  ) async {
    final List<String> existing = viewModel.existingDishNames;
    final bool allExist = viewModel.allDishesExist;
    if (existing.isEmpty) {
      await _offerDraftCombine(viewModel);
      return;
    }

    final String message = allExist
        ? 'Every dish on this form is already listed at "$placeName", so '
              'there is nothing to add. Nothing was submitted.'
        : 'Already listed at "$placeName" and not added again: '
              '${existing.join(', ')}.';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.check_circle_outline,
        title: allExist ? 'Nothing to add' : 'Already on the menu',
        message: message,
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (allExist) {
      await viewModel.finishAsAlreadyThere();
      if (!mounted) return;
      // No second notice here: the dialog above already said nothing would be
      // added, and this path leaves the form straight away.
      AppNavigator.resetTo(AppRoutes.mainShell);
      return;
    }

    final List<String> removed = viewModel.dropExistingDishes();
    if (!mounted) return;
    if (removed.isNotEmpty) {
      await _showNotice(
        icon: Icons.check_circle_outline,
        title: 'Already listed there',
        message:
            '${removed.join(', ')} - already listed there, so not added '
            'again.',
      );
      if (!mounted) return;
    }
    await _offerDraftCombine(viewModel);
  }

  /// "45 m" / "1.2 km" for the similar-place question - the same wording the
  /// place detail screens use.
  static String _shortDistance(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';

  /// The acknowledgement behind a refused Confirm: the name in the field is
  /// not the name on the captured signboard photo (see
  /// `AddLandmarkViewModel.confirmRestaurant`). The message stays plain - no
  /// score, no model talk - and the dialog asks for a decision, not just
  /// attention: put Gemini's own reading back (which confirms the form), or
  /// keep the typed name and fix it by hand.
  Future<void> _showNameMismatchNotice(AddLandmarkViewModel viewModel) async {
    final String? signboardName = viewModel.signboardDetectedName;
    final bool? useSignboardName = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.storefront_outlined,
        title: 'Name does not match the signboard',
        message: AddLandmarkViewModel.signboardNameMismatchMessage,
        actions: <Widget>[
          if (signboardName != null)
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Use the signboard name'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep my name'),
          ),
        ],
      ),
    );
    if (!mounted || useSignboardName != true || signboardName == null) return;
    viewModel.useSignboardName();
    if (!mounted) return;
    // The field now IS Gemini's reading, so this click needs no re-check and
    // carries on where the refused one left off (the merge offer included).
    await _confirmRestaurant(viewModel);
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
    await _showNotice(
      icon: Icons.library_add_check_outlined,
      title: 'Submissions combined',
      message: _mergeNotice(updated),
    );
  }

  /// The form's ONE acknowledgement frame: centred badge, title, message and a
  /// single OK, all inside [AppDialog] - the same modal every other notice in
  /// this flow uses, so padding, width and alignment can never drift between
  /// them (user request: no snackbars, one consistent pop-up).
  ///
  /// Messages come from the ViewModel, so the wording lives with the rule it
  /// explains; this method only presents it.
  Future<void> _showNotice({
    required IconData icon,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: icon,
        title: title,
        message: message,
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

                    // Same idea for the address: a map fill or a picked
                    // suggestion must reach the field even while it is
                    // focused (the force-sync), otherwise a focus-guarded
                    // sync keeps the tourist's typing responsive.
                    if (_appliedAddressVersion != viewModel.addressVersion) {
                      _addressController.text = viewModel.restaurantAddress;
                      _appliedAddressVersion = viewModel.addressVersion;
                    } else if (!_addressFocusNode.hasFocus &&
                        _addressController.text !=
                            viewModel.restaurantAddress) {
                      _addressController.text = viewModel.restaurantAddress;
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
                                  priceRules: viewModel.priceRules,
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
                                priceRules: viewModel.priceRules,
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
                                isChecking: viewModel.isConfirming,
                                onConfirm: () => _confirmRestaurant(viewModel),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _ContactDetailsSection(
                                phoneController: _phoneController,
                                websiteController: _websiteController,
                                phonePrefix: viewModel.phoneCountryCode,
                                phoneLocalMaxLength:
                                    viewModel.phoneLocalMaxLength,
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
                              const Text(
                                'Location (GPS)',
                                style: AppTextStyles.titleSmall,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Choose the exact spot on the map first - the '
                                'restaurant address below follows the pin.',
                                style: AppTextStyles.bodySmall,
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
                                onRecover: viewModel.adjustedLocation.isKnown
                                    ? viewModel.resetLandmarkLocation
                                    : null,
                                rangeMetres: viewModel.pinRangeMetres,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _RestaurantAddressSection(
                                controller: _addressController,
                                focusNode: _addressFocusNode,
                                maxLength: viewModel.addressMaxLength,
                                error: viewModel.restaurantAddressError,
                                warning: viewModel.restaurantAddressWarning,
                                pinWarning: viewModel.addressPinWarning,
                                mapStatus: viewModel.mapAddressStatus,
                                searchStatus: viewModel.addressSearchStatus,
                                suggestions: viewModel.addressSuggestions,
                                distanceLabel: viewModel.formatDistance,
                                canApplyMapAddress:
                                    viewModel.canApplyMapAddress,
                                onApplyMapAddress:
                                    viewModel.applyMapAddressFromPin,
                                onSelectSuggestion: (AddressSuggestion s) {
                                  _addressFocusNode.unfocus();
                                  viewModel.selectAddressSuggestion(s);
                                },
                                onChanged: viewModel.setRestaurantAddress,
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
                              const SizedBox(height: AppSpacing.xxl),
                            ],
                          ),
                        ),
                        _BottomActions(
                          // `_submitFlowActive` keeps the button disabled from
                          // the tap until the flow's outcome - the pre-flight
                          // question is a network check, so the tap must
                          // visibly take hold right away.
                          canSubmit:
                              viewModel.canSubmit &&
                              !viewModel.isSubmitting &&
                              !_submitFlowActive,
                          isSubmitting: viewModel.isSubmitting,
                          // A failed submit's own message wins: it is the one
                          // thing the tourist must see to fix the form, and
                          // this pinned bar is the only part of the screen
                          // that is always on view.
                          reason:
                              viewModel.submitError ??
                              (viewModel.canSubmit
                                  ? null
                                  : viewModel.canSubmitReason),
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
    required this.priceRules,
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

  /// The form's price rules (see [_PriceRules]) - handed to the price field
  /// so the band and the text rules live in one place.
  final _PriceRules priceRules;

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
      // The card's thumbnail is a square crop - the capture itself opens
      // full-screen (the stored copy when the form came from a draft).
      onImageTap: () => showEnlargedImage(
        context,
        file: image,
        source: imageUrl,
        semanticLabel: 'Captured photo of ${food.name}',
      ),
      footer: _PriceField(
        label: 'Price (MYR)',
        initialValue: price,
        priceRules: priceRules,
        warning: priceWarning,
        suggestedRange: suggestedRange,
        onChanged: onPriceChanged,
      ),
    );
  }
}

/// The price rules every price field on the form follows, produced by
/// `AddLandmarkViewModel.priceRules`: the inclusive band, the field's digit
/// shape, and the two TEXT rules - the while-typing leading-zero rewrite and
/// the on-leave two-decimal format. The rules themselves live in
/// `LandmarkSubmissionLogic`.
typedef _PriceRules = ({
  double minPrice,
  double maxPrice,
  int integralDigits,
  int decimalDigits,
  String rangeText,
  String Function(String text) normaliseEntryText,
  String Function(String text) formatEntryText,
});

/// A single price entry field. STRICTLY capped + formatted so pasted content
/// (words, Chinese characters, markup - anything that is not digits and one
/// dot) can never enter: max 7 characters, at most 4 integral digits and 2
/// decimals, inside the band the ViewModel hands over (0.01-9999.99 MYR).
///
/// Two text rules ride [priceRules]:
///   * WHILE TYPING a leading zero is rewritten on the spot - "01" shows
///     "1.00", a pasted "0010.00" shows "10.00" - so a displayed price can
///     never start with 0 (the lone "0" of a "0.50" entry in progress is
///     untouched);
///   * once the field is LEFT every valid price shows exactly two decimals -
///     "1" -> "1.00", "1.5" -> "1.50".
///
/// Shows a precise inline error under the field when the value is unparsable
/// or outside the allowed range.
///
/// The box IS the field: one bordered `TextField` with a fixed "RM" prefix
/// inside it - no money icon and no wrapper container (the label sits
/// directly on top of the box, like the other fields' labels do).
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
    required this.priceRules,
    this.warning,
    this.suggestedRange,
  });

  final String label;
  final double? initialValue;
  final ValueChanged<double> onChanged;

  /// The form's price rules (see [_PriceRules]).
  final _PriceRules priceRules;

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
  /// '9999.99' is the widest allowed value (0.01-9999.99 MYR, 2 decimals).
  static const int _maxLength = 7;

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toStringAsFixed(2) ?? '',
    );
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Leaving the field normalises a valid price to exactly two decimals
  /// ("1" -> "1.00", "1.5" -> "1.50") - the same money format the field
  /// opens with when a value is already known. Not a value change.
  void _onFocusChanged() {
    if (_focusNode.hasFocus) return;
    final String formatted = widget.priceRules.formatEntryText(
      _controller.text,
    );
    if (formatted == _controller.text) return;
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _onChanged(String raw) {
    final String value = raw.trim();
    String? error;
    double? parsed;
    if (value.isNotEmpty) {
      // The formatter already guarantees digits + one dot; this check is
      // the range one (plus the odd mid-entry state like "." or "0").
      parsed = _parse(value);
      if (parsed == null) {
        error = 'Use numbers only, up to 2 decimals (e.g. 12.50).';
      } else if (parsed < widget.priceRules.minPrice ||
          parsed > widget.priceRules.maxPrice) {
        error = 'Price must be between ${widget.priceRules.rangeText}.';
      }
    }
    if (error != _error) setState(() => _error = error);
    if (parsed != null) widget.onChanged(parsed);
  }

  /// A trailing dot is a natural mid-entry state ("12.") that Dart will not
  /// parse - and "." alone is not a number yet.
  static double? _parse(String text) {
    final String parseable = text.endsWith('.')
        ? text.substring(0, text.length - 1)
        : text;
    if (parseable.isEmpty) return null;
    return double.tryParse(parseable);
  }

  @override
  Widget build(BuildContext context) {
    // ONE box, drawn by this widget (the money icon is gone, so the "Price
    // (MYR)" label sits straight on top of it, like the other fields on the
    // form), with the currency mark as plain fixed text inside it.
    //
    // The mark CANNOT be an `InputDecoration.prefixText`: Flutter only paints
    // a prefix while the field is focused or non-empty, so "RM" vanished the
    // moment an empty field lost focus and the hint was all that was left.
    // As a `Row` child it is permanently there, like the phone field's "+60".
    final Color borderColor = _error != null
        ? AppColors.error
        : (widget.warning != null ? AppColors.warning : AppColors.outline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label, style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: <Widget>[
              // Fixed, never part of the editable value - it can neither be
              // deleted nor typed over.
              Text(
                'RM',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  maxLength: _maxLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: <TextInputFormatter>[
                    _DecimalInputFormatter(
                      maxIntegralDigits: widget.priceRules.integralDigits,
                      maxFractionDigits: widget.priceRules.decimalDigits,
                      normalise: widget.priceRules.normaliseEntryText,
                    ),
                  ],
                  onChanged: _onChanged,
                  // The box around the input IS the frame above; the field
                  // itself stays borderless, and the same colour in every
                  // state (this form's boxes do not change on focus).
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    counterText: '',
                    hintText: '0.00',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
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
/// after it, and never more than one dot. It also applies [normalise], which
/// rewrites text that must never be DISPLAYED as typed (a leading zero -
/// "01" shows "1.00"); content the shape check rejects - words, Chinese
/// characters, a second dot - is dropped entirely (the old value is kept).
class _DecimalInputFormatter extends TextInputFormatter {
  const _DecimalInputFormatter({
    required this.maxIntegralDigits,
    required this.maxFractionDigits,
    required this.normalise,
  });

  final int maxIntegralDigits;
  final int maxFractionDigits;

  /// The while-typing rewrite (see `_PriceField`'s doc); receives text that
  /// already passed the shape check and returns it unchanged when there is
  /// nothing to rewrite.
  final String Function(String text) normalise;

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
    if (!pattern.hasMatch(text)) return oldValue;
    final String rewritten = normalise(text);
    if (rewritten == text) return newValue;
    return TextEditingValue(
      text: rewritten,
      selection: TextSelection.collapsed(offset: rewritten.length),
    );
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
                    hintText: 'e.g. Restoran Nasi Kandar Pelita',
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
    this.leadingText,
    this.warning,
    this.status,
    this.statusColor = AppColors.textSecondary,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.focusNode,
    this.inputFormatters = const <TextInputFormatter>[],
  });

  final String label;
  final IconData icon;
  final String hint;
  final TextEditingController controller;

  /// Extra input formatters, applied AFTER the control-character guard - the
  /// phone field uses one to keep its value digits-only.
  final List<TextInputFormatter> inputFormatters;

  /// Fixed, NON-EDITABLE text shown inside the field before the input - the
  /// phone's "+60" country code, which is never part of the editable value
  /// (so it can neither be deleted nor typed over).
  final String? leadingText;

  /// Optional focus node - the address field needs one so the map and the
  /// suggestion dropdown can keep their hands off while the tourist types.
  final FocusNode? focusNode;
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
              if (leadingText != null) ...<Widget>[
                Text(
                  leadingText!,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: <TextInputFormatter>[
                    // Blocks newlines and all control bytes from pasted text.
                    FilteringTextInputFormatter.deny(
                      RegExp(r'[\x00-\x1F\x7F]'),
                    ),
                    ...inputFormatters,
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
///
/// A name that was edited away from Gemini's signboard reading is re-checked
/// against the photo first, so [isChecking] shows that wait on the button
/// itself (disabled, so the question cannot be asked twice).
class _ConfirmRestaurantRow extends StatelessWidget {
  const _ConfirmRestaurantRow({
    required this.confirmed,
    required this.onConfirm,
    this.isChecking = false,
  });

  final bool confirmed;

  /// True while the edited-name check is in flight - see the class doc.
  final bool isChecking;
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
        onPressed: isChecking ? null : onConfirm,
        icon: isChecking
            ? const SizedBox(
                width: AppSizes.inlineNoticeIconSize,
                height: AppSizes.inlineNoticeIconSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline, size: 18),
        label: Text(isChecking ? 'Checking the signboard…' : 'Confirm'),
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
///
/// The phone field carries a FIXED, non-editable [phonePrefix] ("+60") and
/// accepts DIGITS ONLY - no letters, words, symbols or separators can be
/// typed or pasted in. The tourist edits only the national number, and the
/// ViewModel stores it with the country code.
class _ContactDetailsSection extends StatelessWidget {
  const _ContactDetailsSection({
    required this.phoneController,
    required this.websiteController,
    required this.phonePrefix,
    required this.phoneLocalMaxLength,
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

  /// The fixed country-code prefix shown inside the phone field - plain text,
  /// never part of the field's editable value.
  final String phonePrefix;

  /// Cap for the phone's editable (national) part - the fixed prefix already
  /// counts toward the stored cap.
  final int phoneLocalMaxLength;

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
        hint: '123456789',
        leadingText: phonePrefix,
        controller: phoneController,
        maxLength: phoneLocalMaxLength,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          // Numbers only - words, symbols and separators never enter the
          // field, whether typed or pasted.
          FilteringTextInputFormatter.digitsOnly,
        ],
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

/// Optional restaurant address field, BOUND TO THE MAP: OpenStreetMap
/// suggestions appear while the tourist types (nearest first, each labelled
/// with its distance), picking one fills the field - and moves the pin when
/// the place is within the pin range - and the pin itself can fill the field
/// (see `AddLandmarkViewModel`'s address ↔ map section).
///
/// Whatever ends up in the field is validated strictly: letters/digits/spaces
/// plus only `.,-/#`, no leading/trailing or repeated special characters, at
/// least one digit, at least 10 characters, at most its cap (all rules live
/// in `LandmarkSubmissionLogic`, surfaced by `AddLandmarkViewModel`).
class _RestaurantAddressSection extends StatelessWidget {
  const _RestaurantAddressSection({
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.error,
    this.warning,
    this.pinWarning,
    this.mapStatus,
    this.searchStatus,
    this.suggestions = const <AddressSuggestion>[],
    required this.distanceLabel,
    required this.canApplyMapAddress,
    required this.onApplyMapAddress,
    required this.onSelectSuggestion,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final String? error;

  /// Amber warning while the address is close to its cap (see ViewModel).
  final String? warning;

  /// Amber warning after picking a suggestion farther than the pin may move -
  /// the text is kept, the pin stays put, submission stays allowed.
  final String? pinWarning;

  /// "Looking up the address…" / the map lookup's inline notice.
  final String? mapStatus;

  /// The search's running / unavailable / nothing-found line.
  final String? searchStatus;

  /// OpenStreetMap suggestions, nearest first.
  final List<AddressSuggestion> suggestions;

  /// Formats one suggestion's distance ("350 m", "1.2 km").
  final String Function(double metres) distanceLabel;

  /// Whether the pin's own composed address differs from the field's text
  /// and may be applied with one tap.
  final bool canApplyMapAddress;
  final VoidCallback onApplyMapAddress;
  final ValueChanged<AddressSuggestion> onSelectSuggestion;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _FormTextField(
        label: 'Restaurant Address (Optional)',
        icon: Icons.place_outlined,
        hint: 'e.g. 12, Jalan Bukit Bintang, Kuala Lumpur',
        controller: controller,
        focusNode: focusNode,
        maxLength: maxLength,
        maxLines: 2,
        onChanged: onChanged,
        error: error,
        warning: warning,
      ),
      if (pinWarning != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          pinWarning!,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
        ),
      ],
      if (mapStatus != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          mapStatus!,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
      if (canApplyMapAddress) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onApplyMapAddress,
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: const Text("Use the map pin's address"),
          ),
        ),
      ],
      if (suggestions.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.outline),
            borderRadius: AppRadius.cardRadius,
          ),
          // Bounded height: a search can return several places, and an
          // unbounded box pushed the rest of the form off the screen. Up to
          // about four rows show; the rest of the list scrolls inside it.
          constraints: const BoxConstraints(
            maxHeight: AppSizes.addressSuggestionListMaxHeight,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < suggestions.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => onSelectSuggestion(suggestions[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              suggestions[i].address,
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            distanceLabel(suggestions[i].distanceMeters),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // No attribution line here: the map card on this same form already
        // carries "© OpenStreetMap contributors" (see `LocationPickerField`),
        // and a second copy only read as one more confusing status line
        // sitting among the field's errors.
      ],
      if (searchStatus != null && suggestions.isEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          searchStatus!,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ],
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
          // The photo here is cover-cropped to a fixed height, so open it
          // full-screen too - a signboard is hard to read on a crop.
          EnlargeablePhoto(
            onTap: () => showEnlargedImage(
              context,
              file: image,
              source: storedUrl,
              semanticLabel: isSignboard
                  ? 'Captured signboard photo'
                  : 'Captured stall photo',
            ),
            borderRadius: AppRadius.cardRadius,
            child: ClipRRect(
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
    required this.priceRules,
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

  /// The form's price rules (see [_PriceRules]) - handed to every price field
  /// so the band and the text rules live in one place.
  final _PriceRules priceRules;

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
              // Every dish's own capture opens full-screen, like the
              // primary food's.
              onImageTap: () => showEnlargedImage(
                context,
                file: entry.image,
                source: entry.photoRef?.url,
                semanticLabel: 'Captured photo of ${entry.food.name}',
              ),
              footer: Row(
                children: <Widget>[
                  Expanded(
                    child: _PriceField(
                      label: 'Price (MYR)',
                      initialValue: entry.price,
                      priceRules: priceRules,
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
        // Full width like the form's other secondary actions ("Confirm",
        // "Recover to captured location", the two capture buttons) - it used
        // to size to its own label and float against the card edges.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAddMore,
            icon: const Icon(Icons.add),
            label: const Text('Add More Food'),
          ),
        ),
      ],
    );
  }
}

/// The blocking "we are working on it" page, shown as a modal route while a
/// network check owns the form - the submission write ([_submit]) or the
/// near-duplicate check ([_confirmRestaurant]).
///
/// A full-screen barrier covers the whole form - app bar included - so
/// nothing behind it can be tapped, scrolled or typed into, and the
/// [PopScope] keeps the system back button from dropping the page mid-write
/// (a half-written landmark, or a question answered about a name/photo that
/// changed underneath it, is exactly what this page exists to prevent).
///
/// The copy says the wait is EXPECTED. It also matches [AppDialog]'s frame -
/// the app's one modal frame - with a progress ring where the icon badge
/// would sit.
class _BlockingPage extends StatelessWidget {
  const _BlockingPage({required this.title, required this.message});

  /// Centred heading, e.g. "Submitting your landmark…".
  final String title;

  /// Centred body line under the heading - say what is happening and that it
  /// is expected to take a moment.
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
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

  /// The line above the button: why it is disabled, or - once a submit has
  /// actually been attempted - why that attempt failed (see [_submit]).
  /// Null when the form is ready and no failure is outstanding.
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
