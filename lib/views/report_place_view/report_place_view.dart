import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/view_state.dart';
import '../../domain_model/address_suggestion.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/report_claim.dart';
import '../../domain_model/tourist_location.dart';
import '../../view_models/report_place_view_model.dart';
import '../add_landmark_view/widgets/location_picker_field.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/operating_hours_editor.dart';

/// Full-screen report page shared by catalogue restaurants AND submitted
/// landmarks (replaces the old one-shot report bottom sheets). The tourist
/// picks a category, enters the correction, and submits - one claim per
/// specific issue (per corrected day for hours, per item for item reports).
class ReportPlaceView extends StatefulWidget {
  const ReportPlaceView({super.key});

  @override
  State<ReportPlaceView> createState() => _ReportPlaceViewState();
}

class _ReportPlaceViewState extends State<ReportPlaceView> {
  late final ReportPlaceViewModel _viewModel;
  bool _didStart = false;

  @override
  void initState() {
    super.initState();
    _viewModel = ReportPlaceViewModel();
    final (ReportPlaceKind, int, String, TouristLocation)? handoff =
        ReportPlaceHandoff().take();
    if (handoff != null) {
      _viewModel.configure(handoff.$1, handoff.$2, handoff.$3, handoff.$4);
    }
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _start() {
    if (_didStart) return;
    _didStart = true;
    _viewModel.onInit();
  }

  @override
  Widget build(BuildContext context) {
    _start();
    return ChangeNotifierProvider<ReportPlaceViewModel>.value(
      value: _viewModel,
      child: Consumer<ReportPlaceViewModel>(
        builder: (BuildContext context, ReportPlaceViewModel viewModel, Widget? _) {
          return Scaffold(
            appBar: AppTopBar(
              title:
                  'Report ${viewModel.placeName.isEmpty ? 'Place' : viewModel.placeName}',
              showBackButton: true,
            ),
            body: SafeArea(child: _buildBody(context, viewModel)),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ReportPlaceViewModel viewModel) {
    if (viewModel.state == ViewState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            viewModel.errorMessage ?? 'Could not open the report page.',
          ),
        ),
      );
    }
    return ListView(
      padding: AppSpacing.screenPadding,
      children: <Widget>[
        Text('What is wrong?', style: AppTextStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your report is counted with other tourists - a fix is applied once '
          'enough people report the same thing.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        RadioGroup<ReportCategory>(
          groupValue: viewModel.selectedCategory,
          onChanged: (ReportCategory? value) {
            if (value == null) return;
            viewModel.selectCategory(value);
          },
          child: Column(
            children: <Widget>[
              for (final ReportCategory category in ReportCategory.values)
                _CategoryTile(category: category),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (viewModel.selectedCategory != null) ...<Widget>[
          _CategoryBody(
            key: ValueKey<ReportCategory>(viewModel.selectedCategory!),
            category: viewModel.selectedCategory!,
            viewModel: viewModel,
          ),
        ],
        if (viewModel.formError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            viewModel.formError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton.icon(
          onPressed: viewModel.isSubmitting ? null : () => _submit(viewModel),
          icon: viewModel.isSubmitting
              ? const SizedBox.square(
                  dimension: AppSpacing.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.flag_outlined),
          label: const Text('Submit Report'),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Future<void> _submit(ReportPlaceViewModel viewModel) async {
    await viewModel.submit();
    if (!mounted) return;
    _showOutcome(context, viewModel);
  }

  void _showOutcome(BuildContext context, ReportPlaceViewModel viewModel) {
    final String message;
    if (viewModel.requiresSignIn) {
      message =
          'Sign in to report this place. Please sign in from the profile page and try again.';
    } else if (viewModel.reportFailed) {
      message = 'Sorry, your report could not be sent. Please try again.';
    } else if (viewModel.alreadyReported) {
      message = 'You have already reported this. Thanks for looking out!';
    } else if (viewModel.appliedMessage.isNotEmpty) {
      message = viewModel.appliedMessage;
    } else if (viewModel.reportSubmitted) {
      message = 'Report received. Thank you for helping keep the map accurate.';
    } else {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    final bool hiddenPlace = viewModel.placeHiddenNow;
    final bool leavePage = hiddenPlace || viewModel.reportSubmitted;
    viewModel.consumeOutcome();
    // A report that hid the place (froze/removed it) hides its pin - leave the
    // report page (and the caller's detail page pops on its own result) so the
    // now-hidden pin is no longer shown.
    if (leavePage && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(hiddenPlace);
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final ReportCategory category;

  static const Map<ReportCategory, String> _labels = <ReportCategory, String>{
    ReportCategory.operatingHours: 'Operating hours are wrong',
    ReportCategory.itemPrice: 'A menu item price is wrong',
    ReportCategory.itemNotExist: 'A menu item does not exist',
    ReportCategory.address: 'The address is wrong',
    ReportCategory.closedPermanently: 'This place is closed permanently',
    ReportCategory.closedTemporarily: 'This place is closed temporarily',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: RadioListTile<ReportCategory>(
        value: category,
        title: Text(_labels[category]!),
      ),
    );
  }
}

/// Per-category input section. Built with a ValueKey per category so switching
/// category rebuilds from scratch (no stale field state).
class _CategoryBody extends StatelessWidget {
  const _CategoryBody({
    super.key,
    required this.category,
    required this.viewModel,
  });

  final ReportCategory category;
  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    switch (category) {
      case ReportCategory.operatingHours:
        return _HoursBody(viewModel: viewModel);
      case ReportCategory.itemPrice:
        return _ItemPriceBody(viewModel: viewModel);
      case ReportCategory.itemNotExist:
        return _ItemNotExistBody(viewModel: viewModel);
      case ReportCategory.address:
        return _AddressBody(viewModel: viewModel);
      case ReportCategory.closedPermanently:
        return const _ClosedPermanentlyBody();
      case ReportCategory.closedTemporarily:
        return _ClosedTemporarilyBody(viewModel: viewModel);
    }
  }
}

class _HoursBody extends StatelessWidget {
  const _HoursBody({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OperatingHoursEditor(
          operatingHours: viewModel.hours,
          onStatusChanged: viewModel.setDayStatus,
          onRangeTimeChanged: viewModel.setRangeTime,
          onAddRange: viewModel.addTimeRange,
          onRemoveRange: viewModel.removeTimeRange,
          title: 'Correct Operating Hours',
          helperText:
              'Only change the days that are wrong - days you leave untouched '
              'are not reported.',
        ),
        if (viewModel.hoursError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            viewModel.hoursError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _ItemPriceBody extends StatelessWidget {
  const _ItemPriceBody({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Which item?', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        _ItemListBody(viewModel: viewModel),
        if (viewModel.itemError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            viewModel.itemError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        if (viewModel.selectedItem != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            'New price for "${viewModel.selectedItem!.name}"',
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,4}(\.\d{0,2})?'),
              ),
            ],
            decoration: const InputDecoration(
              labelText: 'Price (MYR)',
              prefixText: 'RM ',
            ).copyWith(errorText: viewModel.priceError),
            onChanged: viewModel.setPriceText,
          ),
        ],
      ],
    );
  }
}

class _ItemNotExistBody extends StatelessWidget {
  const _ItemNotExistBody({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Which item is not there?', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        _ItemListBody(viewModel: viewModel),
        if (viewModel.itemError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            viewModel.itemError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _ItemListBody extends StatelessWidget {
  const _ItemListBody({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.itemsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (viewModel.itemsError != null) {
      return Text(
        viewModel.itemsError!,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
      );
    }
    if (viewModel.items.isEmpty) {
      return const Text('No items are listed for this place right now.');
    }
    return RadioGroup<ReportableMenuItem>(
      groupValue: viewModel.selectedItem,
      onChanged: (ReportableMenuItem? value) {
        if (value == null) return;
        viewModel.selectItem(value);
      },
      child: Column(
        children: <Widget>[
          for (final ReportableMenuItem item in viewModel.items)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: RadioListTile<ReportableMenuItem>(
                value: item,
                title: Text(item.name),
                subtitle: Text(
                  item.price == null
                      ? 'Price not listed'
                      : 'RM ${item.price!.toStringAsFixed(2)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddressBody extends StatefulWidget {
  const _AddressBody({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  State<_AddressBody> createState() => _AddressBodyState();
}

/// The address report, BOUND TO A MAP exactly like the Add-New-Landmark
/// form's address field (user request: "the address we should implement just
/// like our landmark get the location"): an OpenStreetMap opens on the spot
/// the app currently places the place, the tourist taps the correct spot,
/// OpenStreetMap suggestions appear while they type (nearest first, each
/// labelled with its distance) and picking one moves the pin there - and the
/// pin's own composed address can fill the field with one tap. There is no
/// 100 m pin allowance here: a wrong pin may be wrong by a lot.
class _AddressBodyState extends State<_AddressBody> {
  final TextEditingController _controller = TextEditingController();
  int _syncedVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.viewModel.addressText;
    _syncedVersion = widget.viewModel.addressVersion;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ReportPlaceViewModel viewModel = widget.viewModel;
    // The ViewModel fills the field from the map (a suggestion, the pin's own
    // address) - the controller has to catch up with those writes, while
    // never fighting the tourist's typing.
    if (viewModel.addressVersion != _syncedVersion) {
      _syncedVersion = viewModel.addressVersion;
      _controller.text = viewModel.addressText;
    }
    final TouristLocation pin = viewModel.reportLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (pin.isKnown) ...<Widget>[
          const Text(
            'Tap the map to set the correct spot',
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          LocationPickerField(
            center: pin,
            pin: pin,
            onMove: viewModel.moveReportLocation,
            errorMessage: viewModel.mapAddressStatus,
            // No pin allowance on this page - see the class doc.
            rangeMetres: null,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        const Text(
          'What is the correct address?',
          style: AppTextStyles.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          maxLines: 2,
          maxLength: viewModel.addressMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
          ],
          decoration: InputDecoration(
            labelText: 'New address',
            hintText: 'e.g. 12, Jalan Bukit Bintang, Kuala Lumpur',
            // The Add-Landmark form hides the counter and nags in amber
            // instead - same field, same behaviour.
            counterText: '',
            errorText: viewModel.addressError,
          ),
          onChanged: viewModel.setAddressText,
        ),
        if (viewModel.addressError == null &&
            viewModel.addressWarning != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            viewModel.addressWarning!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
          ),
        ],
        if (viewModel.canApplyMapAddress) ...<Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: viewModel.applyMapAddressFromPin,
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: const Text("Use the map pin's address"),
            ),
          ),
        ],
        if (viewModel.addressSuggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          _SuggestionList(viewModel: viewModel),
        ],
        if (viewModel.addressSearchStatus != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            viewModel.addressSearchStatus!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// The OpenStreetMap suggestions under the address field - the same box the
/// Add-Landmark form shows (bounded height, one row per place with its
/// distance), because a search can return several and an unbounded list would
/// push the rest of the page off the screen.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final List<AddressSuggestion> suggestions = viewModel.addressSuggestions;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: AppRadius.cardRadius,
      ),
      constraints: const BoxConstraints(
        maxHeight: AppSizes.addressSuggestionListMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            for (int i = 0; i < suggestions.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1),
              InkWell(
                onTap: () => viewModel.selectAddressSuggestion(suggestions[i]),
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
                        viewModel.formatDistance(suggestions[i].distanceMeters),
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
    );
  }
}

class _ClosedPermanentlyBody extends StatelessWidget {
  const _ClosedPermanentlyBody();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Once enough tourists report the same thing, the place is hidden from '
      'the map.',
      style: AppTextStyles.bodyMedium,
    );
  }
}

class _ClosedTemporarilyBody extends StatelessWidget {
  const _ClosedTemporarilyBody({required this.viewModel});

  final ReportPlaceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('How long is it closed?', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                keyboardType: TextInputType.number,
                maxLength: 3,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Duration',
                  counterText: '',
                  errorText: viewModel.closureError,
                  errorMaxLines: 2,
                ),
                onChanged: viewModel.setClosureAmountText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: DropdownButtonFormField<ClosureUnit>(
                initialValue: viewModel.closureUnit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: <DropdownMenuItem<ClosureUnit>>[
                  const DropdownMenuItem<ClosureUnit>(
                    value: ClosureUnit.days,
                    child: Text('Days'),
                  ),
                  const DropdownMenuItem<ClosureUnit>(
                    value: ClosureUnit.months,
                    child: Text('Months'),
                  ),
                ],
                onChanged: (ClosureUnit? value) {
                  if (value != null) viewModel.setClosureUnit(value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The place is hidden during the closure and returns automatically '
          'after the most-reported duration.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
