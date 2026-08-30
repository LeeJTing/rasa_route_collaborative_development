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
  /// The restriction ids are loaded directly because the imported schema has
  /// more than one relationship to `dietary_restriction`, which makes an
  /// implicit PostgREST embed ambiguous.
  Future<List<DietaryRestriction>> restrictionsForFood(int localFoodId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodDietaryRestriction,
      columns: 'dietary_restriction_id',
      eq: <String, Object?>{'local_food_id': localFoodId},
    );
    return _restrictionsByIds(
      rows
          .map(
            (Map<String, dynamic> row) =>
                JsonReader.asIntOrNull(row['dietary_restriction_id']),
          )
          .whereType<int>()
          .toSet(),
    );
  }

  /// Every dish's dietary-restriction ids (`food_dietary_restriction` joined
  /// with `dietary_restriction`) as `local_food_id -> [dietary_restriction_id]`.
  ///
  /// One query for the whole catalogue, so pairing never needs an N+1 lookup
  /// per dish. Dishes without any restriction are simply absent from the map.
  Future<Map<int, List<int>>> restrictionIdsByFood() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodDietaryRestriction,
      columns: 'local_food_id, dietary_restriction_id',
    );
    final Map<int, List<int>> ids = <int, List<int>>{};
    for (final Map<String, dynamic> row in rows) {
      final int? foodId = JsonReader.asIntOrNull(row['local_food_id']);
      final int? restrictionId = JsonReader.asIntOrNull(
        row['dietary_restriction_id'],
      );
      if (foodId == null || restrictionId == null) continue;
      ids.putIfAbsent(foodId, () => <int>[]).add(restrictionId);
    }
    return ids;
  }

  /// Resolves the auth user id (`tourist.id`) to the domain `tourist_id`
  /// before reading the join table. Those UUIDs are different columns in the
  /// ERD and cannot be used interchangeably.
  Future<List<DietaryRestriction>> restrictionsForCurrentTourist() async {
    final String authUserId = api.currentUserId;
    if (authUserId.isEmpty) return const <DietaryRestriction>[];
    final Map<String, dynamic>? tourist = await api.selectOne(
      APIManager.tableTourist,
      columns: 'tourist_id',
      eq: <String, Object?>{'id': authUserId},
    );
    final String touristId =
        JsonReader.asStringOrNull(tourist?['tourist_id']) ?? '';
    return restrictionsForTourist(touristId);
  }

  /// The restrictions for one domain tourist id. Callers that only have an
  /// auth user id must use [restrictionsForCurrentTourist] first.
  Future<List<DietaryRestriction>> restrictionsForTourist(
    String touristId,
  ) async {
    if (touristId.isEmpty) return const <DietaryRestriction>[];
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableUserDietaryRestriction,
      columns: 'dietary_restriction_id',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    return _restrictionsByIds(
      rows
          .map(
            (Map<String, dynamic> row) =>
                JsonReader.asIntOrNull(row['dietary_restriction_id']),
          )
          .whereType<int>()
          .toSet(),
    );
  }

  Future<List<DietaryRestriction>> _restrictionsByIds(Set<int> ids) async {
    if (ids.isEmpty) return const <DietaryRestriction>[];
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableDietaryRestriction,
      inFilter: <String, List<Object?>>{
        'dietary_restriction_id': ids.cast<Object?>().toList(),
      },
      orderBy: 'restriction_name',
    );
    return rows
        .map(DietaryRestrictionDataModel.fromJson)
        .map(
          (DietaryRestrictionDataModel data) => DietaryRestriction(
            id: data.dietaryRestrictionId,
            name: data.restrictionName,
          ),
        )
        .toList(growable: false);
  }
}
