import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

enum FoodSortOrder { ascending, descending }

enum FoodFilterGroup { category, mealType, taste, foodType }

/// Search, filters, favourites and compare-selection state for the catalogue.
class LocalFoodListViewModel extends BaseViewModel {
  LocalFoodListViewModel();

  @protected
  FoodLogicFacade createFoodLogic() => FoodLogicFacade();

  late final FoodLogicFacade foodLogic = createFoodLogic();

  /// Catalogue names are short. Capping hostile/pasted input keeps filtering
  /// responsive and prevents a single-line search field from retaining an
  /// effectively unbounded invisible tail.
  static const int maximumSearchLength = 80;

  static const Map<FoodFilterGroup, List<String>> filterOptions =
      <FoodFilterGroup, List<String>>{
        FoodFilterGroup.category: <String>[
          'Malay',
          'Chinese',
          'Indian',
          'Nyonya',
          'Sabah',
          'Sarawak',
        ],
        FoodFilterGroup.mealType: <String>[
          'All-Day Dining',
          'Breakfast',
          'Brunch',
          'Lunch',
          'High Tea',
          'Dinner',
          'Supper',
          'Street Food',
        ],
        FoodFilterGroup.taste: <String>[
          'Sweet',
          'Salty',
          'Sour',
          'Bitter',
          'Umami',
          'Spicy',
          'Mild',
          'Buttery',
          'Peppery',
          'Savoury',
          'Rich',
          'Light',
          'Creamy',
          'Smoky',
          'Roasted',
          'Fresh',
          'Herbal',
          'Nutty',
          'Earthy',
          'Fermented',
          'Tangy',
          'Fragrant',
          'Refreshing',
        ],
        FoodFilterGroup.foodType: <String>[
          'Food',
          'Beverage',
          'Fruit',
          'Dessert',
          'Kuih',
        ],
      };

  List<LocalFood> _foods = const <LocalFood>[];
  String _query = '';
  FoodSortOrder _sortOrder = FoodSortOrder.ascending;
  final Map<FoodFilterGroup, Set<String>> _filters =
      <FoodFilterGroup, Set<String>>{
        for (final FoodFilterGroup group in FoodFilterGroup.values)
          group: <String>{},
      };
  final Set<int> _selectedIds = <int>{};
  final Set<int> _favouriteUpdates = <int>{};
  bool _isSelecting = false;
  int _loadGeneration = 0;

  String get query => _query;
  FoodSortOrder get sortOrder => _sortOrder;
  Set<int> get selectedIds => Set<int>.unmodifiable(_selectedIds);
  bool get isSelecting => _isSelecting;
  bool get hasFilters =>
      _filters.values.any((Set<String> values) => values.isNotEmpty);
  int get activeFilterCount => _filters.values.fold<int>(
    0,
    (int total, Set<String> values) => total + values.length,
  );

  bool isFilterSelected(FoodFilterGroup group, String value) =>
      _filters[group]!.contains(value);

  List<LocalFood> get displayedFoods {
    final String needle = _query.toLowerCase();
    final List<LocalFood> result = _foods.where((LocalFood food) {
      final bool matchesSearch =
          needle.isEmpty || food.name.toLowerCase().contains(needle);
      return matchesSearch && _matchesFilters(food);
    }).toList();
    result.sort(
      (LocalFood a, LocalFood b) => _sortOrder == FoodSortOrder.ascending
          ? a.name.compareTo(b.name)
          : b.name.compareTo(a.name),
    );
    return result;
  }

  bool _matchesFilters(LocalFood food) {
    final Map<FoodFilterGroup, Set<String>> values =
        <FoodFilterGroup, Set<String>>{
          FoodFilterGroup.category: _splitValues(food.category),
          FoodFilterGroup.mealType: _splitValues(food.mealType),
          FoodFilterGroup.taste: food.tastes.toSet(),
          FoodFilterGroup.foodType: _splitValues(food.foodType),
        };
    for (final FoodFilterGroup group in FoodFilterGroup.values) {
      final Set<String> selected = _filters[group]!;
      if (selected.isNotEmpty &&
          selected.intersection(values[group]!).isEmpty) {
        return false;
      }
    }
    return true;
  }

  Set<String> _splitValues(String raw) => raw
      .split(RegExp(r'[,;/|]'))
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toSet();

  @override
  Future<void> onInit() => loadFoods();

  Future<void> loadFoods() async {
    final int generation = ++_loadGeneration;
    setBusy();
    try {
      final List<LocalFood> foods = await foodLogic.getLocalFoods();
      if (generation != _loadGeneration) return;
      _foods = foods;
      final Set<int> availableIds = foods
          .map((LocalFood food) => food.id)
          .toSet();
      _selectedIds.removeWhere((int id) => !availableIds.contains(id));
      setReady();
    } catch (error, stackTrace) {
      if (generation == _loadGeneration) setError(error, stackTrace);
    }
  }

  void updateSearch(String value) {
    final String trimmed = value.trim();
    _query = trimmed.runes.length <= maximumSearchLength
        ? trimmed
        : String.fromCharCodes(trimmed.runes.take(maximumSearchLength));
    safeNotifyListeners();
  }

  void toggleSort() {
    _sortOrder = _sortOrder == FoodSortOrder.ascending
        ? FoodSortOrder.descending
        : FoodSortOrder.ascending;
    safeNotifyListeners();
  }

  void setSortOrder(FoodSortOrder value) {
    if (_sortOrder == value) return;
    _sortOrder = value;
    safeNotifyListeners();
  }

  void toggleFilter(FoodFilterGroup group, String value) {
    final Set<String> selected = _filters[group]!;
    selected.contains(value) ? selected.remove(value) : selected.add(value);
    safeNotifyListeners();
  }

  void clearFilters() {
    for (final Set<String> values in _filters.values) {
      values.clear();
    }
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

  Future<String?> toggleFavourite(int id) async {
    if (!_favouriteUpdates.add(id)) return null;
    try {
      final bool isFavourite = await foodLogic.toggleFavouriteFood(id);
      _foods = _foods
          .map(
            (LocalFood food) =>
                food.id == id ? food.copyWith(isFavourite: isFavourite) : food,
          )
          .toList(growable: false);
      safeNotifyListeners();
      return null;
    } catch (error) {
      final String message = error.toString();
      return message.startsWith('Exception: ')
          ? message.substring('Exception: '.length)
          : message;
    } finally {
      _favouriteUpdates.remove(id);
    }
  }

  void reset() {
    _query = '';
    _sortOrder = FoodSortOrder.ascending;
    for (final Set<String> values in _filters.values) {
      values.clear();
    }
    _selectedIds.clear();
    _isSelecting = false;
    safeNotifyListeners();
  }
}
