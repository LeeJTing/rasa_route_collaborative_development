import '../../shared_client/api_manager/api_manager.dart';

/// Canonical taste/category options from `food_preference`.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class FoodPreferenceRepository {
  FoodPreferenceRepository();

  final APIManager api = APIManager();

  /// The canonical taste values (`food_preference.preferred_taste`) - the
  /// reference set taste tags are normalised against (Sweet, Salty, Sour,
  /// Spicy, Rich, ...). Deduplicated, empty values dropped.
  Future<List<String>> tasteOptions() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodPreference,
      columns: 'preferred_taste',
    );
    return <String>{
      for (final Map<String, dynamic> row in rows)
        if (row['preferred_taste'] is String &&
            (row['preferred_taste'] as String).isNotEmpty)
          row['preferred_taste'] as String,
    }.toList(growable: false);
  }
}
