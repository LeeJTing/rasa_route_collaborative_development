import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

enum FoodSortOrder { ascending, descending }

/// Search, filters, favourites and compare-selection state for the catalogue.
class LocalFoodListViewModel extends BaseViewModel {
  final FoodLogicFacade foodLogic = FoodLogicFacade();

  List<LocalFood> _foods = const <LocalFood>[];
  String _query = '';
  FoodSortOrder _sortOrder = FoodSortOrder.ascending;
  final Set<String> _filters = <String>{};
  final Set<int> _selectedIds = <int>{};
  bool _isSelecting = false;

  String get query => _query;
  FoodSortOrder get sortOrder => _sortOrder;
  Set<String> get filters => Set<String>.unmodifiable(_filters);
  Set<int> get selectedIds => Set<int>.unmodifiable(_selectedIds);
  bool get isSelecting => _isSelecting;

  List<String> get availableFilters {
    final Set<String> values = <String>{};
    for (final LocalFood food in _foods) {
      values.addAll(
        <String>[
          food.category,
          food.mealType,
          food.cookingStyle,
        ].where((String value) => value.isNotEmpty),
      );
    }
    return values.toList()..sort();
  }

  List<LocalFood> get displayedFoods {
    final String needle = _query.toLowerCase();
    final List<LocalFood> result = _foods.where((LocalFood food) {
      final bool matchesSearch =
          needle.isEmpty ||
          food.name.toLowerCase().contains(needle) ||
          food.description.toLowerCase().contains(needle) ||
          food.synonyms.any(
            (String item) => item.toLowerCase().contains(needle),
          );
      final Set<String> tags = <String>{
        food.category,
        food.mealType,
        food.cookingStyle,
      };
      final bool matchesFilters =
          _filters.isEmpty || _filters.every(tags.contains);
      return matchesSearch && matchesFilters;
    }).toList();
    result.sort(
      (LocalFood a, LocalFood b) => _sortOrder == FoodSortOrder.ascending
          ? a.name.compareTo(b.name)
          : b.name.compareTo(a.name),
    );
    return result;
  }

  @override
  Future<void> onInit() => loadFoods();

  Future<void> loadFoods() => runGuarded(() async {
    _foods = await foodLogic.getLocalFoods();
  });

  void updateSearch(String value) {
    _query = value.trim();
    safeNotifyListeners();
  }

  void toggleSort() {
    _sortOrder = _sortOrder == FoodSortOrder.ascending
        ? FoodSortOrder.descending
        : FoodSortOrder.ascending;
    safeNotifyListeners();
  }

  void toggleFilter(String value) {
    _filters.contains(value) ? _filters.remove(value) : _filters.add(value);
    safeNotifyListeners();
  }

  void toggleSelectionMode() {
    _isSelecting = !_isSelecting;
    if (!_isSelecting) _selectedIds.clear();
    safeNotifyListeners();
  }

  void toggleSelection(int id) {
    if (!_isSelecting) return;
    _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
    safeNotifyListeners();
  }

  Future<void> toggleFavourite(int id) => runGuarded(() async {
    await foodLogic.toggleFavouriteFood(id);
    _foods = _foods
        .map(
          (LocalFood food) => food.id == id
              ? food.copyWith(isFavourite: !food.isFavourite)
              : food,
        )
        .toList(growable: false);
  }, silent: true);

  void reset() {
    _query = '';
    _sortOrder = FoodSortOrder.ascending;
    _filters.clear();
    _selectedIds.clear();
    _isSelecting = false;
    safeNotifyListeners();
  }
}
