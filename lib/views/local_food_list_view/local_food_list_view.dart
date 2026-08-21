import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../view_models/local_food_list_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/food_filter_controls.dart';
import 'widgets/food_search_bar.dart';
import 'widgets/local_food_card.dart';

class LocalFoodListView extends StatefulWidget {
  const LocalFoodListView({super.key});

  @override
  State<LocalFoodListView> createState() => _LocalFoodListViewState();
}

class _LocalFoodListViewState extends State<LocalFoodListView> {
  late final LocalFoodListViewModel _viewModel;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _viewModel = LocalFoodListViewModel()..onInit();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LocalFoodListViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: AppTopBar(
          title: 'All Local Food',
          showBackButton: Navigator.of(context).canPop(),
          onProfileTap: () => Navigator.pushNamed(context, AppRoutes.profile),
        ),
        body: Consumer<LocalFoodListViewModel>(
          builder:
              (BuildContext context, LocalFoodListViewModel vm, Widget? child) {
                if (vm.state == ViewState.busy && vm.displayedFoods.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vm.state == ViewState.error && vm.displayedFoods.isEmpty) {
                  return _ErrorState(
                    message: vm.errorMessage,
                    onRetry: vm.loadFoods,
                  );
                }
                return Column(
                  children: <Widget>[
                    Padding(
                      padding: AppSpacing.screenPadding,
                      child: Column(
                        children: <Widget>[
                          FoodSearchBar(
                            controller: _searchController,
                            onChanged: vm.updateSearch,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FoodFilterControls(
                            isSelecting: vm.isSelecting,
                            hasFilters: vm.hasFilters,
                            onSort: vm.toggleSort,
                            onFilter: () => _showFilters(context, vm),
                            onSelect: vm.toggleSelectionMode,
                            onReset: () {
                              _searchController.clear();
                              vm.reset();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: vm.displayedFoods.isEmpty
                          ? const Center(
                              child: Text('No local food matches your search.'),
                            )
                          : ListView.separated(
                              padding: AppSpacing.screenPadding.copyWith(
                                bottom: AppSpacing.xl,
                              ),
                              itemCount: vm.displayedFoods.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (BuildContext context, int index) {
                                final food = vm.displayedFoods[index];
                                return LocalFoodCard(
                                  food: food,
                                  isSelecting: vm.isSelecting,
                                  isSelected: vm.selectedIds.contains(food.id),
                                  onTap: () {
                                    if (vm.isSelecting) {
                                      vm.toggleSelection(food.id);
                                    } else {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.foodDetail,
                                        arguments: food.id,
                                      );
                                    }
                                  },
                                  onFavourite: () =>
                                      vm.toggleFavourite(food.id),
                                );
                              },
                            ),
                    ),
                    if (vm.isSelecting && vm.selectedIds.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: AppSpacing.cardPadding,
                        color: AppColors.surfaceVariant,
                        child: Text(
                          '${vm.selectedIds.length} selected for comparison',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                  ],
                );
              },
        ),
      ),
    );
  }

  Future<void> _showFilters(
    BuildContext context,
    LocalFoodListViewModel vm,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (BuildContext context) =>
        ChangeNotifierProvider<LocalFoodListViewModel>.value(
          value: vm,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            maxChildSize: 0.92,
            builder: (BuildContext context, ScrollController controller) =>
                Consumer<LocalFoodListViewModel>(
                  builder:
                      (
                        BuildContext context,
                        LocalFoodListViewModel vm,
                        _,
                      ) => ListView(
                        controller: controller,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Filter local food',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              TextButton(
                                onPressed: vm.clearFilters,
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                          ...FoodFilterGroup.values.map(
                            (FoodFilterGroup group) => _FilterGroup(
                              title: _filterTitle(group),
                              values:
                                  LocalFoodListViewModel.filterOptions[group]!,
                              isSelected: (String value) =>
                                  vm.isFilterSelected(group, value),
                              onToggle: (String value) =>
                                  vm.toggleFilter(group, value),
                            ),
                          ),
                        ],
                      ),
                ),
          ),
        ),
  );

  String _filterTitle(FoodFilterGroup group) => switch (group) {
    FoodFilterGroup.category => 'Food Category',
    FoodFilterGroup.mealType => 'Meal Type',
    FoodFilterGroup.taste => 'Taste',
    FoodFilterGroup.foodType => 'Food Type',
  };
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.title,
    required this.values,
    required this.isSelected,
    required this.onToggle,
  });

  final String title;
  final List<String> values;
  final bool Function(String) isSelected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: values
              .map(
                (String value) => FilterChip(
                  label: Text(value),
                  selected: isSelected(value),
                  onSelected: (_) => onToggle(value),
                ),
              )
              .toList(growable: false),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message ?? 'Unable to load local food.'),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
