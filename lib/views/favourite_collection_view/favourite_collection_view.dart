import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/favourite_collection_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import 'widgets/favourite_food_card.dart';

/// Saved dishes screen.
///
/// One card per favourited dish. Swiping a card left reveals the delete
/// action and removes it from the collection (the mock-up's swiped state).
/// Tapping a card opens the dish's detail screen.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class FavouriteCollectionView extends StatefulWidget {
  const FavouriteCollectionView({super.key});

  @override
  State<FavouriteCollectionView> createState() =>
      _FavouriteCollectionViewState();
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
        appBar: const AppTopBar(title: 'Favourite Food Collection'),
        body: SafeArea(
          child: Consumer<FavouriteCollectionViewModel>(
            builder:
                (
                  BuildContext context,
                  FavouriteCollectionViewModel viewModel,
                  Widget? _,
                ) {
                  if (viewModel.state == ViewState.busy &&
                      viewModel.favourites.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (viewModel.state == ViewState.error &&
                      viewModel.favourites.isEmpty) {
                    return AsyncMessage(
                      icon: Icons.favorite_border,
                      title: "Couldn't load your favourite foods",
                      message: viewModel.errorMessage,
                      actionLabel: 'Retry',
                      onAction: viewModel.load,
                    );
                  }
                  if (viewModel.favourites.isEmpty) {
                    return const AsyncMessage(
                      icon: Icons.favorite_border,
                      title: 'No favourite foods yet',
                      message:
                          'Tap the heart on any dish to save it here.\n'
                          'Swipe a card left to remove it.',
                    );
                  }
                  return ListView.separated(
                    padding: AppSpacing.screenPadding,
                    itemCount: viewModel.favourites.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (BuildContext context, int index) {
                      final LocalFood food = viewModel.favourites[index];
                      return Dismissible(
                        key: ValueKey<int>(food.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => viewModel.removeFavourite(food),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: AppRadius.cardRadius,
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: AppColors.onPrimary,
                          ),
                        ),
                        child: FavouriteFoodCard(
                          food: food,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.foodDetail,
                            arguments: food.id,
                          ),
                        ),
                      );
                    },
                  );
                },
          ),
        ),
      ),
    );
  }
}
