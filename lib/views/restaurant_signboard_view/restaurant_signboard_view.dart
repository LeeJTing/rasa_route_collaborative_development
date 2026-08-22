import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/restaurant_signboard_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Restaurant signboard / stall image capture screen.
///
/// Dual-purpose camera interface:
/// - Signboard capture: Extracts restaurant name via Gemini
/// - Stall image capture: Validates frame completeness via Gemini
///
/// User chooses ONE; other button becomes disabled (greyed).
///
/// Placeholder - implement from `UC500_VIEW_LAYER_STRUCTURE.md`.
class RestaurantSignboardView extends StatefulWidget {
  const RestaurantSignboardView({super.key});

  @override
  State<RestaurantSignboardView> createState() =>
      _RestaurantSignboardViewState();
}

class _RestaurantSignboardViewState extends State<RestaurantSignboardView> {
  late final RestaurantSignboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = RestaurantSignboardViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RestaurantSignboardViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Add New Landmark'),
        body: SafeArea(
          child: Consumer<RestaurantSignboardViewModel>(
            builder:
                (
                  BuildContext context,
                  RestaurantSignboardViewModel viewModel,
                  Widget? _,
                ) {
                  return Padding(
                    padding: AppSpacing.screenPadding,
                    child: const Center(child: Text('RestaurantSignboardView')),
                  );
                },
          ),
        ),
      ),
    );
  }
}
