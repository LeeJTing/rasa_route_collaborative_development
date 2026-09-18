import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/routing/report_place_handoff.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/tourist_location.dart';
import '../../view_models/restaurant_detail_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/enlarged_image_dialog.dart';
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
                bottomNavigationBar: restaurant == null
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: OutlinedButton.icon(
                            onPressed: () => _openReport(restaurant),
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('Report Restaurant'),
                          ),
                        ),
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
        RestaurantDetailHeader(
          restaurant: restaurant,
          onImageTap: () => showEnlargedImage(
            context,
            semanticLabel: restaurant.name,
            source: restaurant.imageUrl,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        RestaurantInformationSection(
          restaurant: restaurant,
          onAddressTap: () => _openRestaurantMap(restaurant),
          onPhoneTap: () => _launchExternal(
            Uri(scheme: 'tel', path: restaurant.phone.trim()),
            failureMessage: 'Unable to open the phone app.',
          ),
          onWebsiteTap: () => _openWebsite(restaurant.website),
        ),
        const SizedBox(height: AppSpacing.xl),
        RestaurantMenuPreview(
          items: restaurant.items,
          onImageTap: (item) => showRestaurantItemImage(
            context,
            semanticLabel: item.foodName,
            source: item.imageUrl,
            fromLinkedFood: item.imageFromLinkedFood,
          ),
        ),
      ],
    );
  }

  /// Opens the full-screen report page (shared by restaurants and landmarks).
  /// The place rides [ReportPlaceHandoff] - routes pass no arguments (see
  /// `AppNavigator` / the codebase's handoff convention). Its coordinates ride
  /// along too: the address report's map opens on the spot the app currently
  /// places this restaurant. If the report froze or removed the place, the
  /// page pops `true` and this screen leaves too so the now-hidden pin is no
  /// longer shown. A successful report that keeps the place visible pops
  /// `false`; in that case this screen reloads the corrected details.
  Future<void> _openReport(Restaurant restaurant) async {
    final double? latitude = restaurant.latitude;
    final double? longitude = restaurant.longitude;
    ReportPlaceHandoff()
      ..pendingKind = ReportPlaceKind.restaurant
      ..pendingPlaceId = restaurant.id
      ..pendingName = restaurant.name
      ..pendingLocation = latitude == null || longitude == null
          ? TouristLocation.unknown
          : TouristLocation(latitude: latitude, longitude: longitude);
    final bool? hidPlace = await AppNavigator.push<bool>(AppRoutes.reportPlace);
    if (!mounted || hidPlace == null) return;
    if (hidPlace) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
      return;
    }
    await _viewModel.refresh();
  }

  Future<void> _openRestaurantMap(Restaurant restaurant) async {
    final double? latitude = restaurant.latitude;
    final double? longitude = restaurant.longitude;
    final String query = latitude != null && longitude != null
        ? '$latitude,$longitude'
        : restaurant.address.trim();
    await _launchExternal(
      Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': query,
      }),
      failureMessage: 'Unable to open the map application.',
    );
  }

  Future<void> _openWebsite(String rawWebsite) async {
    final String value = rawWebsite.trim();
    final Uri? parsed = Uri.tryParse(value);
    final Uri? uri =
        parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')
        ? parsed
        : Uri.tryParse('https://$value');
    if (uri == null || uri.host.isEmpty) {
      _showLaunchFailure('This restaurant website is invalid.');
      return;
    }
    await _launchExternal(
      uri,
      failureMessage: 'Unable to open the restaurant website.',
    );
  }

  Future<void> _launchExternal(
    Uri uri, {
    required String failureMessage,
  }) async {
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _showLaunchFailure(failureMessage);
    } catch (_) {
      _showLaunchFailure(failureMessage);
    }
  }

  void _showLaunchFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
