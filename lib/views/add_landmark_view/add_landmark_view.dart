import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/add_landmark_view_model.dart';
import '../../view_models/food_recognition_view_model.dart'
    show LandmarkDraftHandoff;
import '../common_widgets/app_top_bar.dart';
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
    _phoneController = TextEditingController(text: _viewModel.restaurantPhone);
    _websiteController = TextEditingController(
      text: _viewModel.restaurantWebsite,
    );
    _addressController = TextEditingController(
      text: _viewModel.restaurantAddress,
    );
    _appliedRestaurantNameVersion = _viewModel.extractedRestaurantNameVersion;
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _restaurantNameController.dispose();
    _restaurantNameFocusNode.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
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
                              maxLength: viewModel.restaurantNameMaxLength,
                              error: viewModel.restaurantName.isEmpty
                                  ? null
                                  : viewModel.restaurantNameError,
                              warning: viewModel.restaurantNameWarning,
                              onChanged: viewModel.setRestaurantName,
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
                              onPhoneChanged: viewModel.setRestaurantPhone,
                              onWebsiteChanged: viewModel.setRestaurantWebsite,
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
                              center: viewModel.currentLocation,
                              pin: viewModel.adjustedLocation.isKnown
                                  ? viewModel.adjustedLocation
                                  : viewModel.currentLocation,
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

/// A single price entry field. STRICTLY capped + formatted so a pasted blob
/// can never overflow: max 7 characters, digits and one dot only, at most 4
/// integer digits and 2 decimals (the 0.01-1000 MYR rule). Shows a precise
/// inline error under the field when the value is unparsable or outside the
/// allowed range; Gemini's soft price warning only shows while the value is
/// otherwise valid.
class _PriceField extends StatefulWidget {
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
      ],
    );
  }
}

/// Optional phone + website fields under the restaurant name. Both optional;
/// when the tourist types anything the ViewModel validates it (Malaysian
/// phone format; http(s) URL format - reachability is checked at submit).
class _ContactDetailsSection extends StatelessWidget {
  const _ContactDetailsSection({
    required this.phoneController,
    required this.websiteController,
    required this.phoneMaxLength,
    required this.websiteMaxLength,
    required this.phoneError,
    required this.websiteError,
    required this.websiteWarning,
    required this.onPhoneChanged,
    required this.onWebsiteChanged,
  });

  final TextEditingController phoneController;
  final TextEditingController websiteController;
  final int phoneMaxLength;
  final int websiteMaxLength;
  final String? phoneError;
  final String? websiteError;

  /// Amber warning while the website is in its 76-79 warn zone.
  final String? websiteWarning;
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
