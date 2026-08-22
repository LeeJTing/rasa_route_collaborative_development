import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../view_models/dashboard_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Rasa Route screen.
///
/// Placeholder body. What is wired up is the View - ViewModel connection:
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
///
/// Build the layout from the Figma frame for this screen, using
/// `Theme.of(context)` and the tokens in `lib/app/theme/`. Reusable pieces go
/// in `dashboard_view/widgets/`.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late final DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Rasa Route'),
        body: SafeArea(
          child: Consumer<DashboardViewModel>(
            builder:
                (
                  BuildContext context,
                  DashboardViewModel viewModel,
                  Widget? _,
                ) {
                  return Padding(
                    padding: AppSpacing.screenPadding,
                    child: ListView(
                      children: <Widget>[
                        Text(
                          'Discover Malaysia through food',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Find nearby places or learn the stories behind local dishes.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _DiscoveryCard(
                          title: 'Quick Mode',
                          subtitle: 'Restaurants near your current location',
                          icon: Icons.near_me_outlined,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.restaurantRecommendation,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _DiscoveryCard(
                          title: 'All Local Food',
                          subtitle: 'Browse, filter and save Malaysian dishes',
                          icon: Icons.ramen_dining_outlined,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.localFoodList,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _DiscoveryCard(
                          title: 'Prawn Noodle',
                          subtitle: 'Open the featured food story',
                          icon: Icons.menu_book_outlined,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.foodDetail,
                            arguments: 1,
                          ),
                        ),
                      ],
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}
