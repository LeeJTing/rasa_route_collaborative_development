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
///
/// EXPIRY: a claim older than `reportClaimLifetime` (one year) no longer
/// counts toward its threshold AND no longer blocks its tourist from
/// reporting the issue again - every read filters expired rows out
/// (user request, 2026-09-14).
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
      columns: 'report_id, created_at',
      eq: <String, Object?>{..._issueEq(claim), 'tourist_id': touristId},
    );
    // A claim past its one-year lifetime no longer blocks the tourist (the
    // report "expired" - see `reportClaimLifetime`), so a stale row alone
    // must not read as "already reported".
    return rows.any((Map<String, dynamic> row) => !_isExpired(row));
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
  /// Only claims the on-site check verified count (`location_valid`), and
  /// claims past their one-year lifetime never count
  /// (`reportClaimLifetime`).
  Future<int> countIdentical(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'report_id, created_at',
      eq: <String, Object?>{
        ..._issueEq(claim),
        'payload': claim.payload,
        'location_valid': true,
      },
    );
    return rows.where((Map<String, dynamic> row) => !_isExpired(row)).length;
  }

  /// How many DISTINCT tourists have claimed this ISSUE at all (regardless of
  /// payload) - used by categories whose claims accumulate across different
  /// payloads and only agree on the payload at apply time. Today that is
  /// [ReportCategory.closedTemporarily]: a place reported "closed
  /// temporarily" with different durations still counts toward ONE threshold
  /// of 10; the agreed END DATE is resolved only when the fix is applied
  /// (see `ReportModerationRules.resolveClosureUntil`).
  Future<int> countIssue(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'report_id, created_at',
      eq: <String, Object?>{..._issueEq(claim), 'location_valid': true},
    );
    return rows.where((Map<String, dynamic> row) => !_isExpired(row)).length;
  }

  /// Every VALID pin recorded for [claim]'s identical group - the raw
  /// material for the pin consensus (`ReportModerationRules`
  /// `consensusLocation`), read at apply time because the rows are cleared
  /// once the fix lands.
  Future<List<TouristLocation>> locationsForIssue(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'latitude, longitude, created_at',
      eq: <String, Object?>{
        ..._issueEq(claim),
        'payload': claim.payload,
        'location_valid': true,
      },
    );
    return <TouristLocation>[
      for (final Map<String, dynamic> row in rows)
        if (!_isExpired(row) &&
            row['latitude'] is num &&
            row['longitude'] is num)
          TouristLocation(
            latitude: (row['latitude'] as num).toDouble(),
            longitude: (row['longitude'] as num).toDouble(),
          ),
    ];
  }

  /// Every temporary-closure claim of [claim]'s ISSUE (regardless of the
  /// caller's own payload), each with its `created_at` - the raw material for
  /// the closure resolution (`ReportModerationRules.resolveClosureUntil`),
  /// which normalises every claim to the END DATE the voter meant.
  ///
  /// Mirrors [countIssue]'s filter: only on-site-verified claims
  /// (`location_valid`) vote, so an off-site claim can never steer the end
  /// date without contributing to the threshold, and expired claims are
  /// dropped (`reportClaimLifetime`).
  Future<List<ClosureClaim>> closureClaimsForIssue(ReportClaim claim) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableReport,
      columns: 'payload, created_at',
      eq: <String, Object?>{..._issueEq(claim), 'location_valid': true},
    );
    final List<ClosureClaim> claims = <ClosureClaim>[];
    for (final Map<String, dynamic> row in rows) {
      if (_isExpired(row)) continue;
      final Object? payload = row['payload'];
      final Object? created = row['created_at'];
      if (payload is! String || created is! String) continue;
      final DateTime? at = DateTime.tryParse(created);
      if (at == null) continue;
      claims.add(ClosureClaim(payload: payload, createdAt: at));
    }
    return claims;
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

  /// `report.created_at` -> expired? Claims stop counting (and stop blocking
  /// their tourist) one year after they were filed - see
  /// `reportClaimLifetime`.
  bool _isExpired(Map<String, dynamic> row) {
    final Object? raw = row['created_at'];
    final DateTime? created = raw is String ? DateTime.tryParse(raw) : null;
    return isReportClaimExpired(created, DateTime.now());
  }
}
