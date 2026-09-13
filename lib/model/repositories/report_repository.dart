import '../../domain_model/report_claim.dart';
import '../../domain_model/tourist_location.dart';
import '../../shared_client/api_manager/api_manager.dart';

/// Writes to the ONE shared `report` table (see the migrations that create and
/// reshape it). A row is one CLAIM: `(kind, place_id, reason, item_kind?,
/// item_id?, day?, payload, tourist_id?, created_at)`.
///
/// "One tourist may report a specific issue once" is enforced by the table's
/// partial unique index `report_one_per_issue_idx`
/// (kind, place_id, reason, item_kind, item_id, day, tourist_id) WHERE
/// tourist_id IS NOT NULL - so before inserting we check [alreadyReported]
/// and skip the duplicate. Identical claims (same issue, same canonical
/// [ReportClaim.payload]) are counted with [countIdentical]; the matched rows
/// are cleared with [deleteIdentical] once the fix is applied.
class ReportRepository {
  ReportRepository();

  final APIManager api = APIManager();

  static const String kindLandmark = 'landmark';
  static const String kindRestaurant = 'restaurant';

  /// Whether [touristId] has already claimed [claim] (the same issue - same
  /// place, reason, item and day).
  Future<bool> alreadyReported({
    required ReportClaim claim,
    required String touristId,
  }) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'report_id',
      eq: <String, Object?>{..._issueEq(claim), 'tourist_id': touristId},
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Records ONE claim row. [touristId] is null only for anonymous reporters
  /// (reporting is signed-in-only in the app, so this is normally set).
  Future<void> insertClaim({
    required ReportClaim claim,
    String? touristId,
  }) async {
    await api.insertRow(APIManager.tableReport, <String, dynamic>{
      'kind': claim.placeKind.columnValue,
      'place_id': claim.placeId,
      'reason': claim.category.name,
      'item_kind': claim.itemKind?.columnValue,
      'item_id': claim.itemId,
      'day': claim.day?.name,
      'payload': claim.payload,
      // The report page's pin, on the address claim only (null everywhere
      // else) - see `ReportClaim.latitude`.
      'latitude': claim.latitude,
      'longitude': claim.longitude,
      // Whether the reporter was on site - only valid claims count.
      'location_valid': claim.locationValid,
      'tourist_id': touristId,
    });
  }

  /// How many DISTINCT tourists have made the identical claim (same issue,
  /// same canonical payload) - the value the threshold is checked against.
  ///
  /// Only claims the on-site check verified count (`location_valid`).
  Future<int> countIdentical(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'report_id',
      eq: <String, Object?>{
        ..._issueEq(claim),
        'payload': claim.payload,
        'location_valid': true,
      },
    );
    return rows.length;
  }

  /// How many DISTINCT tourists have claimed this ISSUE at all (regardless of
  /// payload) - used by categories whose claims accumulate across different
  /// payloads and only agree on the payload at apply time. Today that is
  /// [ReportCategory.closedTemporarily]: a place reported "closed
  /// temporarily" with different durations still counts toward ONE threshold
  /// of 10; the most-common reported duration is picked only when the fix is
  /// applied (see `ReportModerationRules.resolveMostCommonClosure`).
  Future<int> countIssue(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'report_id',
      eq: <String, Object?>{..._issueEq(claim), 'location_valid': true},
    );
    return rows.length;
  }

  /// Every VALID pin recorded for [claim]'s identical group - the raw
  /// material for the pin consensus (`ReportModerationRules`
  /// `consensusLocation`), read at apply time because the rows are cleared
  /// once the fix lands.
  Future<List<TouristLocation>> locationsForIssue(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'latitude, longitude',
      eq: <String, Object?>{
        ..._issueEq(claim),
        'payload': claim.payload,
        'location_valid': true,
      },
    );
    return <TouristLocation>[
      for (final Map<String, dynamic> row in rows)
        if (row['latitude'] is num && row['longitude'] is num)
          TouristLocation(
            latitude: (row['latitude'] as num).toDouble(),
            longitude: (row['longitude'] as num).toDouble(),
          ),
    ];
  }

  /// Every claim payload recorded for [claim]'s issue (regardless of the
  /// caller's own payload) - used to resolve the most-common temporary-closure
  /// duration at apply time.
  Future<List<String>> payloadsForIssue(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'payload',
      eq: _issueEq(claim),
    );
    return <String>[
      for (final Map<String, dynamic> row in rows)
        if (row['payload'] is String) row['payload'] as String,
    ];
  }

  /// Deletes every row matching the identical claim (same issue + same
  /// payload) - called AFTER the fix is applied so future reports start a
  /// fresh count. (Delete grant comes from migration 20260910010000.)
  Future<void> deleteIdentical(ReportClaim claim) async {
    await api.deleteRows(
      APIManager.tableReport,
      eq: <String, Object?>{..._issueEq(claim), 'payload': claim.payload},
    );
  }

  /// Deletes every row of one ISSUE (regardless of payload) - e.g. when an
  /// item is removed, its price/not-exist claims are no longer meaningful.
  Future<void> deleteIssue(ReportClaim claim) async {
    await api.deleteRows(APIManager.tableReport, eq: _issueEq(claim));
  }

  /// The eq filter identifying the ISSUE a claim is about - everything except
  /// the tourist and the payload.
  Map<String, Object?> _issueEq(ReportClaim claim) => <String, Object?>{
    'kind': claim.placeKind.columnValue,
    'place_id': claim.placeId,
    'reason': claim.category.name,
    if (claim.itemKind != null) 'item_kind': claim.itemKind!.columnValue,
    if (claim.itemId != null) 'item_id': claim.itemId,
    if (claim.day != null) 'day': claim.day!.name,
  };
}
