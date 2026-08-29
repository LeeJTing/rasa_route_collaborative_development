import '../../core/json_model.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/dietary_restriction_data_model.dart';

/// Reference dietary restrictions (`dietary_restriction` table) plus the two
/// many-to-many link tables that attach them to dishes and to tourists:
/// `food_dietary_restriction` and `user_dietary_restriction`.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class DietaryRestrictionRepository {
  DietaryRestrictionRepository();

  final APIManager api = APIManager();

  /// All dietary restrictions, alphabetically.
  Future<List<DietaryRestriction>> restrictions() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableDietaryRestriction,
      orderBy: 'restriction_name',
    );
    return rows
        .map((Map<String, dynamic> row) {
      final DietaryRestrictionDataModel data =
      DietaryRestrictionDataModel.fromJson(row);
      return DietaryRestriction(
        id: data.dietaryRestrictionId,
        name: data.restrictionName,
      );
    })
        .toList(growable: false);
  }

  /// The restrictions attached to one dish via `food_dietary_restriction`.
  /// A dish with no link (null) is allowed - it simply has no restrictions.
  /// Uses the FK embed `dietary_restriction(...)` so the link table's FK
  /// column name never has to be referenced directly.
  Future<List<DietaryRestriction>> restrictionsForFood(int localFoodId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodDietaryRestriction,
      columns: 'dietary_restriction(dietary_restriction_id, restriction_name)',
      eq: <String, Object?>{'local_food_id': localFoodId},
    );
    return rows
        .map(_fromRow)
        .whereType<DietaryRestriction>()
        .toList(growable: false);
  }

  /// Every dish's dietary-restriction ids (`food_dietary_restriction` joined
  /// with `dietary_restriction`) as `local_food_id -> [dietary_restriction_id]`.
  ///
  /// One query for the whole catalogue, so pairing never needs an N+1 lookup
  /// per dish. Dishes without any restriction are simply absent from the map.
  Future<Map<int, List<int>>> restrictionIdsByFood() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodDietaryRestriction,
      columns:
      'local_food_id, dietary_restriction(dietary_restriction_id, restriction_name)',
    );
    final Map<int, List<int>> ids = <int, List<int>>{};
    for (final Map<String, dynamic> row in rows) {
      final int? foodId = JsonReader.asIntOrNull(row['local_food_id']);
      final DietaryRestriction? restriction = _fromRow(row);
      if (foodId == null || restriction == null) continue;
      ids.putIfAbsent(foodId, () => <int>[]).add(restriction.id);
    }
    return ids;
  }

  Future<List<DietaryRestriction>> restrictionsForTourist(
      String touristId,
      ) async {
    if (touristId.isEmpty) return const <DietaryRestriction>[];
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableUserDietaryRestriction,
      columns: 'dietary_restriction(dietary_restriction_id, restriction_name)',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    return rows
        .map(_fromRow)
        .whereType<DietaryRestriction>()
        .toList(growable: false);
  }

  /// All food-to-restriction links in one request, grouped for queue ranking.
  /// A bulk query avoids one Supabase round trip for every swipe card.
  Future<Map<int, Set<int>>> restrictionIdsByFood() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodDietaryRestriction,
      columns: 'local_food_id, dietary_restriction_id',
    );
    final Map<int, Set<int>> grouped = <int, Set<int>>{};
    for (final Map<String, dynamic> row in rows) {
      final int? foodId = JsonReader.asIntOrNull(row['local_food_id']);
      final int? restrictionId = JsonReader.asIntOrNull(
        row['dietary_restriction_id'],
      );
      if (foodId == null || restrictionId == null) continue;
      grouped.putIfAbsent(foodId, () => <int>{}).add(restrictionId);
    }
    return grouped;
  }

  /// Parses one link row. Returns null when the embedded restriction is null
  /// so a food with no dietary restriction is allowed (treated as none).
  DietaryRestriction? _fromRow(Map<String, dynamic> row) {
    final Map<String, dynamic> embedded = JsonReader.asMap(
      row['dietary_restriction'],
    );
    final int? id = JsonReader.asIntOrNull(embedded['dietary_restriction_id']);
    if (id == null) return null;
    final String name =
        JsonReader.asStringOrNull(embedded['restriction_name']) ??
        'Restriction $id';
    return DietaryRestriction(id: id, name: name);
  }
}
