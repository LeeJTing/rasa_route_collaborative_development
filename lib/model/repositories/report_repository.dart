import '../../shared_client/api_manager/api_manager.dart';

/// Writes to the ONE shared `report` table (see the migration that creates
/// it). A row is `(kind, place_id, reason, tourist_id?, created_at)` where
/// [kindLandmark] / [kindRestaurant] pick which place a row refers to.
///
/// "One tourist may report a place once" is enforced by the table's partial
/// unique index (kind, place_id, tourist_id) WHERE tourist_id IS NOT NULL -
/// so when we know who is reporting we check [alreadyReported] first and
/// skip the duplicate insert.
class ReportRepository {
  ReportRepository();

  final APIManager api = APIManager();

  static const String kindLandmark = 'landmark';
  static const String kindRestaurant = 'restaurant';

  /// Whether [touristId] has already reported [placeId] of [kind].
  Future<bool> alreadyReported({
    required String kind,
    required int placeId,
    required String touristId,
  }) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'report_id',
      eq: <String, Object?>{
        'kind': kind,
        'place_id': placeId,
        'tourist_id': touristId,
      },
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Records one report row. [touristId] is null until auth is wired in.
  Future<void> insertReport({
    required String kind,
    required int placeId,
    required String reason,
    String? touristId,
  }) async {
    await api.insertRow(APIManager.tableReport, <String, dynamic>{
      'kind': kind,
      'place_id': placeId,
      'reason': reason,
      'tourist_id': touristId,
    });
  }
}
