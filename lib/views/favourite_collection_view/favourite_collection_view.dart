import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/favourite_collection_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Saved dishes screen.
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
/// in `favourite_collection_view/widgets/`.
class FavouriteCollectionView extends StatefulWidget {
  const FavouriteCollectionView({super.key});

  @override
  State<FavouriteCollectionView> createState() => _FavouriteCollectionViewState();
}

class _FavouriteCollectionViewState extends State<FavouriteCollectionView> {
  late final FavouriteCollectionViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = FavouriteCollectionViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FavouriteCollectionViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Saved dishes'),
        body: SafeArea(
          child: Consumer<FavouriteCollectionViewModel>(
            builder: (BuildContext context, FavouriteCollectionViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('FavouriteCollectionView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
