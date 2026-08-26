import '../../domain_model/dietary_restriction.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/dietary_restriction_data_model.dart';

/// Reference dietary restrictions (`dietary_restriction` table).
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
}
