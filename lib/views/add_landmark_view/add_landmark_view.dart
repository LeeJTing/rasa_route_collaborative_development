import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/opening_hour.dart';
import '../../view_models/add_landmark_view_model.dart';
import '../../view_models/food_recognition_view_model.dart'
    show LandmarkDraftHandoff;
import '../common_widgets/app_top_bar.dart';
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

class _AddLandmarkViewState extends State<AddLandmarkView> {
  late final AddLandmarkViewModel _viewModel;

  // The restaurant name can be set two ways: typed by the tourist, or
  // auto-filled from a signboard capture (setExtractedRestaurantName). A
  // plain `initialValue`-based TextFormField only reads its value once and
  // ignores later Provider rebuilds, so it would miss the auto-fill. A
  // persistent controller, synced only while the field ISN'T focused, gets
  // both right without fighting the tourist's own typing.
  late final TextEditingController _restaurantNameController;
  final FocusNode _restaurantNameFocusNode = FocusNode();

  /// Last signboard-extraction version applied to `_restaurantNameController`
  /// (see the force-sync in `build` - a fresh extraction must overwrite the
  /// tourist's typed name even while the field is focused).
  int _appliedRestaurantNameVersion = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = AddLandmarkViewModel();

    // Data from the previous screen (the recognized food, and its photo)
    // arrives through the hand-off, since routes carry no arguments and a
    // ViewModel takes no constructor parameters. Set it BEFORE onInit() so
    // the form opens already populated.
    final LocalFood? food = LandmarkDraftHandoff().takeRecognizedFood();
    if (food != null) {
      _viewModel.setRecognizedFood(
        food,
        priceMin: LandmarkDraftHandoff().takePriceMin(),
        priceMax: LandmarkDraftHandoff().takePriceMax(),
        confidence: LandmarkDraftHandoff().takeConfidence(),
        dietaryRestrictions: LandmarkDraftHandoff().takeDietaryRestrictions(),
        dietaryConflicts: LandmarkDraftHandoff().takeDietaryConflicts(),
      );
    }
    final XFile? foodImage = LandmarkDraftHandoff().takeCapturedImage();
    if (foodImage != null) _viewModel.setRecognizedFoodImage(foodImage);

    _restaurantNameController = TextEditingController(
      text: _viewModel.restaurantName,
    );
    _appliedRestaurantNameVersion = _viewModel.extractedRestaurantNameVersion;
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _restaurantNameController.dispose();
    _restaurantNameFocusNode.dispose();
    _viewModel.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddLandmarkViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Add New Landmark'),
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
                                image: viewModel.recognizedFoodImage,
                                price: viewModel.primaryFoodPrice,
                                priceWarning: viewModel.primaryFoodPriceWarning,
                                dietaryConflicts:
                                    viewModel.primaryFoodDietaryConflicts,
                                onPriceChanged: viewModel.setPrimaryFoodPrice,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _AdditionalFoodsSection(
                              entries: viewModel.additionalFoods,
                              onAddMore: viewModel.openAddMoreFood,
                              onPriceChanged: viewModel.setAdditionalFoodPrice,
                              onRemove: viewModel.removeAdditionalFood,
                              priceWarningFor:
                                  viewModel.additionalFoodPriceWarning,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _ImageCaptureRow(
                              capturedImage: viewModel.capturedImage,
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
                              onChanged: viewModel.setRestaurantName,
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
                              center: viewModel.currentLocation,
                              pin: viewModel.adjustedLocation.isKnown
                                  ? viewModel.adjustedLocation
                                  : viewModel.currentLocation,
                              errorMessage: viewModel.locationError,
                              onMove: viewModel.adjustLandmarkLocation,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _OperatingHoursSection(
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
    );
  }
}

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
    required this.image,
    required this.price,
    required this.onPriceChanged,
    this.priceWarning,
    this.dietaryConflicts = const <String>[],
  });

  final LocalFood food;
  final XFile? image;
  final double? price;
  final ValueChanged<double> onPriceChanged;

  /// Optional soft price guidance (Gemini's suggested range) under the field.
  final String? priceWarning;

  /// Restrictions this dish conflicts with - see `RecognisedFoodCard`.
  final List<String> dietaryConflicts;

  @override
  Widget build(BuildContext context) {
    return RecognisedFoodCard(
      food: food,
      image: image,
      collapsible: true,
      dietaryConflicts: dietaryConflicts,
      footer: _PriceField(
        label: 'Price (MYR)',
        initialValue: price,
        warning: priceWarning,
        onChanged: onPriceChanged,
      ),
    );
  }
}

/// A single price entry field (A16: rejects nothing itself - the ViewModel
/// validates the 0.01-1000 MYR range and surfaces the error).
class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.warning,
  });

  final String label;
  final double? initialValue;
  final ValueChanged<double> onChanged;

  /// Optional soft price guidance (Gemini's suggested range) shown under the
  /// field - a warning, not an error.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: initialValue?.toStringAsFixed(2) ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: 'RM '),
          onChanged: (String value) {
            final double? parsed = double.tryParse(value);
            if (parsed != null) onChanged(parsed);
          },
        ),
        if (warning != null) ...<Widget>[
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
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
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
            border: Border.all(color: AppColors.outline),
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
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Enter restaurant name',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
  });

  final XFile? capturedImage;
  final String? capturedImageType;
  final bool isSignboardDisabled;
  final bool isStallDisabled;
  final VoidCallback onCaptureSignboard;
  final VoidCallback onCaptureStall;
  final VoidCallback onCancelImage;

  @override
  Widget build(BuildContext context) {
    final XFile? image = capturedImage;
    if (image != null) {
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
                            child: ColoredBox(color: AppColors.surfaceVariant),
                          );
                        }
                        return Image.memory(
                          snapshot.data!,
                          width: double.infinity,
                          height: AppSizes.capturedPhotoPreviewHeight,
                          fit: BoxFit.cover,
                        );
                      },
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

/// Operating hours, one row per day (BF-19..23, A14, A15). Every day has a
/// three-way [DayStatus] (Open / Unknown / Closed) - see `OpeningHour`'s doc
/// for why "Unknown" is a real answer, not just a UI decoration. Only Open
/// gets editable time dropdowns - Unknown has no time to show, so it's
/// rendered dimmed with no interaction, same as Closed.
///
/// A day can have more than one `OpeningHour` row when Open (e.g. a midday
/// closure: "12:00-14:00" then "15:00-20:00") - this directly mirrors the
/// real `OpeningHours` table, where each row independently carries its own
/// `(day, status, opening_time, closing_time)`, rather than a day-level
/// object wrapping a list. Each row gets its own line; the "+" at the end
/// of the last one adds another.
class _OperatingHoursSection extends StatelessWidget {
  const _OperatingHoursSection({
    required this.operatingHours,
    required this.onStatusChanged,
    required this.onRangeTimeChanged,
    required this.onAddRange,
    required this.onRemoveRange,
    required this.onCopyMondayToAll,
  });

  final Map<Weekday, List<OpeningHour>> operatingHours;
  final void Function(Weekday day, DayStatus status) onStatusChanged;
  final void Function(
    Weekday day,
    int rangeIndex,
    bool isOpeningTime,
    int minutes,
  )
  onRangeTimeChanged;
  final void Function(Weekday day) onAddRange;
  final void Function(Weekday day, int rangeIndex) onRemoveRange;
  final VoidCallback onCopyMondayToAll;

  static const Map<Weekday, String> _dayLabels = <Weekday, String>{
    Weekday.monday: 'Mon',
    Weekday.tuesday: 'Tue',
    Weekday.wednesday: 'Wed',
    Weekday.thursday: 'Thu',
    Weekday.friday: 'Fri',
    Weekday.saturday: 'Sat',
    Weekday.sunday: 'Sun',
  };

  @override
  Widget build(BuildContext context) {
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
                    'Operating Hours',
                    style: AppTextStyles.titleSmall,
                  ),
                ),
                // Flexible + ellipsis so the long button label never
                // overflows the card's right edge on narrow screens.
                Flexible(
                  child: TextButton(
                    onPressed: onCopyMondayToAll,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      'Copy Monday to All Weekdays',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        decoration: TextDecoration.underline,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Column headers, precisely aligned with the actual
            // opening/closing dropdowns on each day row below - both share
            // the exact same widths (AppSizes.timeDropdownWidth for each
            // dropdown, an invisible dash the same width as the real "-"
            // separator), so this isn't just an approximate lineup.
            Row(
              children: <Widget>[
                const SizedBox(
                  width:
                      AppSizes.shortDayLabelWidth +
                      AppSizes.compactCheckboxSize +
                      AppSpacing.sm +
                      AppSizes.openLabelSlotWidth,
                ),
                SizedBox(
                  width: AppSizes.timeDropdownWidth,
                  child: Text('Opening', style: AppTextStyles.detailLabel),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: AppSizes.timeDropdownWidth,
                  child: Text('Closing', style: AppTextStyles.detailLabel),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final Weekday day in Weekday.values)
              _DayRow(
                label: _dayLabels[day]!,
                rows: operatingHours[day] ?? const <OpeningHour>[],
                onStatusChanged: (DayStatus status) =>
                    onStatusChanged(day, status),
                onRangeTimeChanged:
                    (int rangeIndex, bool isOpeningTime, int minutes) =>
                        onRangeTimeChanged(
                          day,
                          rangeIndex,
                          isOpeningTime,
                          minutes,
                        ),
                onAddRange: () => onAddRange(day),
                onRemoveRange: (int rangeIndex) =>
                    onRemoveRange(day, rangeIndex),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.rows,
    required this.onStatusChanged,
    required this.onRangeTimeChanged,
    required this.onAddRange,
    required this.onRemoveRange,
  });

  final String label;

  /// This day's `OpeningHour` rows - always at least one (a Closed/Unknown
  /// day has exactly one, with null times; an Open day can have more).
  final List<OpeningHour> rows;
  final ValueChanged<DayStatus> onStatusChanged;
  final void Function(int rangeIndex, bool isOpeningTime, int minutes)
  onRangeTimeChanged;
  final VoidCallback onAddRange;
  final ValueChanged<int> onRemoveRange;

  /// Cycles Closed -> Unknown -> Open -> Closed - one tap on the toggle
  /// advances to the next state.
  static DayStatus _nextStatus(DayStatus current) {
    switch (current) {
      case DayStatus.closed:
        return DayStatus.unknown;
      case DayStatus.unknown:
        return DayStatus.open;
      case DayStatus.open:
        return DayStatus.closed;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Every row shares the same status (the ViewModel keeps it that way),
    // so the first row's status stands for the whole day - there's no
    // separate day-level status field to read now that OpeningHour rows
    // mirror the real table directly.
    final DayStatus status = rows.isNotEmpty
        ? rows.first.status
        : DayStatus.closed;

    // One compact toggle (dash/?/check) instead of three separate
    // checkboxes - tapping it cycles Closed -> Unknown -> Open. That frees
    // up the row to also hold the opening/closing time dropdowns directly
    // alongside the day label. Each row gets its own line; "+" trails the
    // last one to add another, "x" removes one once there's more than one.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: AppSizes.shortDayLabelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(label, style: AppTextStyles.operatingHoursLabel),
            ),
          ),
          _DayStatusToggle(
            status: status,
            onTap: () => onStatusChanged(_nextStatus(status)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: status == DayStatus.open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int i = 0; i < rows.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: i < rows.length - 1 ? AppSpacing.xs : 0,
                          ),
                          // Every row uses the same fixed column widths, so a
                          // newly added row lines up exactly with the rows
                          // above it, and the Opening/Closing boxes sit under
                          // their header titles.
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              // "Open" label - fixed slot, only on the first
                              // row (empty on later rows keeps columns stable).
                              SizedBox(
                                width: AppSizes.openLabelSlotWidth,
                                child: i == 0
                                    ? Text(
                                        'Open',
                                        style: AppTextStyles.bodySmall,
                                      )
                                    : null,
                              ),
                              _TimeDropdown(
                                minutes: rows[i].opensAt,
                                onChanged: (int m) =>
                                    onRangeTimeChanged(i, true, m),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              _TimeDropdown(
                                minutes: rows[i].closesAt,
                                onChanged: (int m) =>
                                    onRangeTimeChanged(i, false, m),
                              ),
                              // Action: "+" on the first row (add another
                              // range), "x" on the rest (remove). Right-aligned
                              // in a flexible slot so it always lines up and
                              // never overflows.
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: i == 0
                                      ? InkWell(
                                          onTap: onAddRange,
                                          child: const Icon(
                                            Icons.add_circle_outline,
                                            size: AppSizes.addRangeIconSize,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : InkWell(
                                          onTap: () => onRemoveRange(i),
                                          child: const Icon(
                                            Icons.close,
                                            size: AppSizes.addRangeIconSize,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      status == DayStatus.unknown
                          ? 'Hours not known'
                          : 'Closed',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Opening/closing time selector - a dropdown list of every 15-minute mark
/// from "00:00" through "24:00" inclusive ("24:00" is its own distinct
/// option, meaning "open until midnight," not the same slot as "00:00").
/// Replaces the old wheel-style `showTimePicker` dialog - the tourist picks
/// straight from the fixed list instead.
class _TimeDropdown extends StatelessWidget {
  const _TimeDropdown({required this.minutes, required this.onChanged});

  /// Minutes since midnight (0-1440). 1440 itself is the "24:00" option.
  final int? minutes;
  final ValueChanged<int> onChanged;

  static const int _stepMinutes = 15;
  static const int _maxMinutes = 24 * 60; // 1440 = "24:00"

  static String _label(int totalMinutes) {
    if (totalMinutes >= _maxMinutes) return '24:00';
    final int hour = totalMinutes ~/ 60;
    final int minute = totalMinutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Rounds to the nearest valid dropdown entry - guards against a stored
  /// value that doesn't land exactly on a 15-minute mark (DropdownButton
  /// throws if its value doesn't match one of its items exactly).
  static int? _snap(int? value) {
    if (value == null) return null;
    final int snapped = ((value / _stepMinutes).round()) * _stepMinutes;
    return snapped.clamp(0, _maxMinutes);
  }

  @override
  Widget build(BuildContext context) {
    // Fixed-width box so it never resizes when the selected time changes
    // ("00:00" vs "24:00" etc.) - the DropdownButton fills it via isExpanded.
    return Container(
      width: AppSizes.timeDropdownWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.timeChipBackground,
        border: Border.all(color: AppColors.textPrimary, width: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _snap(minutes),
          isDense: true,
          isExpanded: true, // Fills the fixed-width container above instead
          // of sizing to its own content, so the arrow
          // sits at the container's true right edge.
          iconSize: AppSizes.compactCheckboxIconSize,
          style: AppTextStyles.bodySmall,
          hint: Text('--:--', style: AppTextStyles.bodySmall),
          items: <DropdownMenuItem<int>>[
            for (int m = 0; m <= _maxMinutes; m += _stepMinutes)
              DropdownMenuItem<int>(value: m, child: Text(_label(m))),
          ],
          onChanged: (int? value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

/// A single compact toggle standing in for the day's status - a dash for
/// Closed (default), a question mark for Unknown, a checkmark for Open.
/// Tapping cycles through all three (see `_DayRow._nextStatus`) rather than
/// showing three separate checkboxes side by side, so the row has room left
/// for the opening/closing time fields next to it.
class _DayStatusToggle extends StatelessWidget {
  const _DayStatusToggle({required this.status, required this.onTap});

  final DayStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    late final Widget glyph;
    switch (status) {
      case DayStatus.open:
        glyph = const Icon(
          Icons.check,
          size: AppSizes.compactCheckboxIconSize,
          color: AppColors.textPrimary,
        );
      case DayStatus.unknown:
        glyph = Text(
          '?',
          style: AppTextStyles.operatingHoursLabel.copyWith(
            color: AppColors.textPrimary,
          ),
        );
      case DayStatus.closed:
        glyph = const Icon(
          Icons.remove,
          size: AppSizes.compactCheckboxIconSize,
          color: AppColors.textSecondary,
        );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        width: AppSizes.compactCheckboxSize,
        height: AppSizes.compactCheckboxSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardBorderWarm,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: glyph,
      ),
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
  });

  final List<LandmarkFoodEntry> entries;
  final VoidCallback onAddMore;
  final void Function(int entryId, double price) onPriceChanged;
  final ValueChanged<int> onRemove;

  /// Returns the soft price guidance for one entry (Gemini's suggested range).
  final String? Function(int entryId) priceWarningFor;

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
              image: entry.image,
              collapsible: true,
              footer: Row(
                children: <Widget>[
                  Expanded(
                    child: _PriceField(
                      label: 'Price',
                      initialValue: entry.price,
                      warning: priceWarningFor(entry.entryId),
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
