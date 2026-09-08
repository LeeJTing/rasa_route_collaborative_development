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
  const RestaurantDetailView({super.key});

  @protected
  RestaurantDetailViewModel createViewModel() => RestaurantDetailViewModel();

  @protected
  int? selectedRestaurantId(BuildContext context) {
    final Object? argument = ModalRoute.of(context)?.settings.arguments;
    return argument is int ? argument : null;
  }

  @override
  State<RestaurantDetailView> createState() => _RestaurantDetailViewState();
}

class _RestaurantDetailViewState extends State<RestaurantDetailView> {
  late final RestaurantDetailViewModel _viewModel;
  bool _didLoadArguments = false;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadArguments) return;
    _didLoadArguments = true;
    _viewModel.selectRestaurant(widget.selectedRestaurantId(context));
    _viewModel.onInit();
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
    if (!mounted || submitted != true) return;
    final String message;
    if (viewModel.requiresSignIn) {
      message =
          'Sign in to report this place. Please sign in from the profile page and try again.';
    } else if (viewModel.reportFailed) {
      message = 'Sorry, your report could not be sent. Please try again.';
    } else if (viewModel.alreadyReported) {
      message = 'You have already reported this restaurant. Thanks for looking out!';
    } else if (viewModel.reportSubmitted) {
      message =
          'Report received. Thank you for helping keep the map accurate.';
    } else {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    final bool leavePage = viewModel.reportFrozePlace;
    viewModel.consumeReportSubmitted();
    // A report that froze the restaurant hides it - leave the page (back to
    // the map) so the now-hidden pin is no longer shown. The ViewModel already
    // asked every live dashboard to drop its caches and re-read, so the map
    // underneath is current by the time the tourist lands on it.
    if (leavePage && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
