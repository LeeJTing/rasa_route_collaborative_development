import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/restaurant.dart';
import '../../view_models/restaurant_detail_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/report_restaurant_sheet.dart';
import 'widgets/restaurant_detail_header.dart';
import 'widgets/restaurant_information_section.dart';
import 'widgets/restaurant_menu_preview.dart';

class RestaurantDetailView extends StatefulWidget {
  const RestaurantDetailView({super.key, @visibleForTesting this.viewModel});

  final RestaurantDetailViewModel? viewModel;

  @override
  State<RestaurantDetailView> createState() => _RestaurantDetailViewState();
}

class _RestaurantDetailViewState extends State<RestaurantDetailView> {
  late final RestaurantDetailViewModel _viewModel;
  bool _didLoadArguments = false;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? RestaurantDetailViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadArguments) return;
    _didLoadArguments = true;
    final Object? argument = ModalRoute.of(context)?.settings.arguments;
    if (argument is int) {
      _viewModel.loadRestaurant(argument);
    } else if (widget.viewModel == null) {
      _viewModel.rejectMissingRestaurantId();
    } else {
      // Injected ViewModels are used by isolated widget tests where there is
      // no named route. Production navigation must always provide the ID.
      _viewModel.loadRestaurant(1);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RestaurantDetailViewModel>.value(
      value: _viewModel,
      child: Consumer<RestaurantDetailViewModel>(
        builder:
            (
              BuildContext context,
              RestaurantDetailViewModel viewModel,
              Widget? _,
            ) {
              final Restaurant? restaurant = viewModel.restaurant;
              return Scaffold(
                appBar: AppTopBar(
                  title: restaurant?.name ?? 'Restaurant Details',
                  showBackButton: true,
                ),
                body: SafeArea(
                  child: _buildBody(context, viewModel, restaurant),
                ),
              );
            },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RestaurantDetailViewModel viewModel,
    Restaurant? restaurant,
  ) {
    if (viewModel.state == ViewState.busy && restaurant == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.state == ViewState.error && restaurant == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                viewModel.errorMessage ?? 'Restaurant details could not load.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: viewModel.retry,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    if (restaurant == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: <Widget>[
        RestaurantDetailHeader(restaurant: restaurant),
        const SizedBox(height: AppSpacing.xl),
        RestaurantInformationSection(restaurant: restaurant),
        const SizedBox(height: AppSpacing.xl),
        RestaurantMenuPreview(items: restaurant.items),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => _showReportSheet(restaurant, viewModel),
          icon: const Icon(Icons.flag_outlined, color: AppColors.error),
          label: const Text('Report Restaurant'),
        ),
      ],
    );
  }

  Future<void> _showReportSheet(
    Restaurant restaurant,
    RestaurantDetailViewModel viewModel,
  ) async {
    final bool? submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (BuildContext sheetContext) => ReportRestaurantSheet(
        restaurantName: restaurant.name,
        onSubmit: viewModel.submitReport,
      ),
    );
    if (!mounted || submitted != true || !viewModel.reportSubmitted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report selected for this UI preview. Backend submission is not available yet.',
        ),
      ),
    );
    viewModel.consumeReportSubmitted();
  }
}
