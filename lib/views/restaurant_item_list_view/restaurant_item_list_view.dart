import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/restaurant_item_list_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Menu screen.
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
/// in `restaurant_item_list_view/widgets/`.
class RestaurantItemListView extends StatefulWidget {
  const RestaurantItemListView({super.key});

  @override
  State<RestaurantItemListView> createState() => _RestaurantItemListViewState();
}

class _RestaurantItemListViewState extends State<RestaurantItemListView> {
  late final RestaurantItemListViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = RestaurantItemListViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RestaurantItemListViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Menu'),
        body: SafeArea(
          child: Consumer<RestaurantItemListViewModel>(
            builder:
                (
                  BuildContext context,
                  RestaurantItemListViewModel viewModel,
                  Widget? _,
                ) {
                  return const Padding(
                    padding: AppSpacing.screenPadding,
                    child: Center(child: Text('RestaurantItemListView')),
                  );
                },
          ),
        ),
      ),
    );
  }
}
