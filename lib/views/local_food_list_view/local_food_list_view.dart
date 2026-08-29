import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/local_food.dart';
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
    _viewModel = LocalFoodListViewModel();
    _viewModel.onInit();
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
                final List<LocalFood> foods = vm.displayedFoods;
                if (vm.state == ViewState.busy && foods.isEmpty) {
                  return const _LoadingState();
                }
                if (vm.state == ViewState.error && foods.isEmpty) {
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
                            activeFilterCount: vm.activeFilterCount,
                            onSort: () => _showSortOptions(context, vm),
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
                      child: RefreshIndicator(
                        onRefresh: vm.loadFoods,
                        child: foods.isEmpty
                            ? _EmptyState(
                                onClear: () {
                                  _searchController.clear();
                                  vm.updateSearch('');
                                  vm.clearFilters();
                                },
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: AppSpacing.screenPadding.copyWith(
                                  bottom: AppSpacing.xl,
                                ),
                                itemCount: foods.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: AppSpacing.md),
                                itemBuilder: (BuildContext context, int index) {
                                  final LocalFood food = foods[index];
                                  return LocalFoodCard(
                                    food: food,
                                    isSelecting: vm.isSelecting,
                                    isSelected: vm.selectedIds.contains(
                                      food.id,
                                    ),
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
                                    onFavourite: () async {
                                      final String? message = await vm
                                          .toggleFavourite(food.id);
                                      if (!context.mounted || message == null) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(message)),
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ),
                    if (vm.isSelecting)
                      Container(
                        width: double.infinity,
                        padding: AppSpacing.cardPadding,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            top: BorderSide(color: AppColors.outline),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                vm.selectedIds.length < 2
                                    ? 'Select at least 2 local foods'
                                    : '${vm.selectedIds.length} selected',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            FilledButton(
                              onPressed: vm.selectedIds.length >= 2
                                  ? () => _openComparison(context, vm)
                                  : null,
                              child: const Text('Compare Foods'),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
        ),
      ),
    );
  }

  Future<void> _showSortOptions(
    BuildContext context,
    LocalFoodListViewModel vm,
  ) => showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (BuildContext context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Sort local food',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<FoodSortOrder>(
              groupValue: vm.sortOrder,
              onChanged: (FoodSortOrder? value) {
                if (value == null) return;
                vm.setSortOrder(value);
                Navigator.pop(context);
              },
              child: const Column(
                children: <Widget>[
                  RadioListTile<FoodSortOrder>(
                    title: Text('Name: A–Z'),
                    value: FoodSortOrder.ascending,
                  ),
                  RadioListTile<FoodSortOrder>(
                    title: Text('Name: Z–A'),
                    value: FoodSortOrder.descending,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

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
            initialChildSize: AppLayoutRatios.catalogueFilterSheetInitial,
            maxChildSize: AppLayoutRatios.catalogueFilterSheetMaximum,
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
                          const SizedBox(height: AppSpacing.xl),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Show ${vm.displayedFoods.length} local food',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                ),
          ),
        ),
  );

  void _openComparison(BuildContext context, LocalFoodListViewModel vm) {
    if (vm.selectedIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least 2 local foods to compare.'),
        ),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.foodComparison,
      arguments: vm.selectedIds.toList(growable: false),
    );
  }

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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(),
        SizedBox(height: AppSpacing.md),
        Text('Loading local food…'),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: AppSpacing.screenPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.search_off_rounded,
                    size: AppSizes.avatarMd,
                    color: AppColors.accentBrown,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No local food found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Try another food name or clear the selected filters.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Clear search and filters'),
                  ),
                ],
              ),
            ),
          ),
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
          const Icon(
            Icons.wifi_off_rounded,
            size: AppSizes.avatarMd,
            color: AppColors.accentBrown,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Local food could not be loaded',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message ?? 'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
