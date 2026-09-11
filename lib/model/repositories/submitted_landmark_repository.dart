import 'dart:developer' as developer;

import '../../core/json_model.dart';
import '../../core/name_normalization.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/landmark_item_data_model.dart';
import '../data_models/opening_hours_data_model.dart';
import '../data_models/submitted_landmark_data_model.dart';

/// Tourist-contributed landmarks and the dishes attached to them.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
///
/// Writes follow the real Supabase tables exactly:
///   * `submitted_landmark` - one row per landmark. `landmark_id` has no
///     identity default, so the app supplies the next id (see [_nextId]).
///   * `landmark_item` - one row per attached dish. `landmark_item_id` IS an
///     identity column, so the DB assigns it.
///   * `opening_hours` - one row per day/range. `opening_hours_id` has no
///     identity default - supplied the same way as `landmark_id`. The table
///     stores the ERD `status` plus nullable times for Closed/Unknown days.
///
/// These writes require RLS insert/update policies - until they are applied,
/// every write is denied (see ARCHITECTURE_ANALYSIS.md, Known Gaps).
class SubmittedLandmarkRepository {
  SubmittedLandmarkRepository();

  final APIManager api = APIManager();

  /// Saves a brand-new landmark - the `submitted_landmark` row, then its
  /// `landmark_item` rows and its `opening_hours` rows. Returns the assigned
  /// `landmark_id`.
  Future<int> save(SubmittedLandmark landmark) async {
    final int landmarkId = landmark.id == 0
        ? await _nextId(APIManager.tableSubmittedLandmark, 'landmark_id')
        : landmark.id;

    await api.insertRow(APIManager.tableSubmittedLandmark, <String, dynamic>{
      'landmark_id': landmarkId,
      'landmark_name': landmark.name,
      'longitude': landmark.longitude,
      'latitude': landmark.latitude,
      'category': landmark.category,
      // A new submission is ALWAYS available with a clean reported count -
      // never frozen (the tourist just reported it as a valid landmark, so
      // it starts visible even if an earlier frozen submission of the same
      // name exists) and never carrying old reports.
      'reported_count': 0,
      'status': 'available',
      // The landmark's own signboard/stall photo, uploaded to Storage by
      // the ViewModel before this save (see [uploadImage]).
      'image_url': landmark.imageUrl,
      'image_id': landmark.imageId,
      'image_category': landmark.imageCategory,
      // Optional tourist-supplied contact/address - written only on a new
      // landmark row (see the AddLandmarkViewModel validation caps). Empty
      // strings are stored as null (cleaner than '' in text columns).
      'phone': landmark.phone.trim().isEmpty ? null : landmark.phone.trim(),
      'website': landmark.website.trim().isEmpty
          ? null
          : landmark.website.trim(),
      'address': landmark.address.trim().isEmpty
          ? null
          : landmark.address.trim(),
    });

    await addItems(landmarkId, landmark.items);
    await _insertOpeningHours(landmarkId, landmark.openingHours);
    return landmarkId;
  }

  /// A13 merge: a tourist re-submitted an EXISTING place, and the submission
  /// carried contact/address details. Writes them onto the existing landmark
  /// row so they are not silently dropped by the merge path (which otherwise
  /// only attaches dishes).
  ///
  /// Merge rule - NEVER clobber richer existing data with an emptier
  /// re-submission:
  ///   * a field the re-submission leaves empty is NEVER written (an existing
  ///     value is kept - never blanked with an empty string);
  ///   * a field whose submitted value equals the stored one is skipped
  ///     (nothing changed, nothing written);
  ///   * only a field the re-submission ACTUALLY changed (different,
  ///     non-empty value) is updated - see [changedContactFields].
  /// Best-effort: a failure here is swallowed by the merge caller.
  Future<void> updateContactFields(
    int landmarkId, {
    String? phone,
    String? website,
    String? address,
  }) async {
    // Read what is stored first so the merge writes ONLY the fields that
    // changed - a second submission that lacks a field must not overwrite it,
    // and a field the second submission did not change is left alone.
    final Map<String, dynamic>? stored = await api.selectOne(
      APIManager.tableSubmittedLandmark,
      columns: 'phone, website, address',
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
    final Map<String, Object?> values = changedContactFields(
      storedPhone: stored?['phone'] as String?,
      storedWebsite: stored?['website'] as String?,
      storedAddress: stored?['address'] as String?,
      phone: phone,
      website: website,
      address: address,
    );
    if (values.isEmpty) return;
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      values,
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// Pure per-field merge decision for [updateContactFields]: given the values
  /// already STORED on the landmark and the values a re-submission carries,
  /// returns the columns to write. A column is written only when the
  /// re-submission's trimmed value is non-empty AND differs from the stored
  /// value - so an existing address/phone/website is never blanked or
  /// needlessly rewritten by a later submission that lacks or repeats it.
  /// Separated from the DB write so the rule is unit-testable.
  static Map<String, Object?> changedContactFields({
    String? storedPhone,
    String? storedWebsite,
    String? storedAddress,
    String? phone,
    String? website,
    String? address,
  }) {
    final Map<String, Object?> values = <String, Object?>{};
    void consider(String column, String? submitted, String? stored) {
      final String? trimmed = submitted?.trim();
      // Not supplied (null/blank) -> never touch the stored value.
      if (trimmed == null || trimmed.isEmpty) return;
      // Unchanged -> skip; only an actual change on this field is written.
      if (trimmed == (stored ?? '').trim()) return;
      values[column] = trimmed;
    }

    consider('phone', phone, storedPhone);
    consider('website', website, storedWebsite);
    consider('address', address, storedAddress);
    return values;
  }

  /// A13 merge: a tourist re-submitted an EXISTING submitted landmark and the
  /// form carried opening hours. Persists ONLY the days the re-submission
  /// actually asserted (Open with times, or Closed) that also DIFFER from the
  /// stored rows - a day left in the form's default "Unknown" state is never
  /// touched, so an emptier second submission never blanks or rewrites hours
  /// an earlier one stored (e.g. Tue-Fri 09:00-14:00 survive a second
  /// submission that only changes Monday).
  ///
  /// Each changed day is replaced row-for-row: the stored rows for that day
  /// are deleted and the submitted rows inserted (a day can carry several
  /// rows when Open - one per range). See [changedOpeningHourDays] for the
  /// pure per-day decision. Best-effort: a failure here is swallowed by the
  /// merge caller. Requires the `opening_hours_delete` RLS policy (see
  /// migration 20260910000000_grant_opening_hours_landmark_delete.sql) - it
  /// only allows deleting rows that belong to a submitted landmark, never
  /// curated restaurant hours.
  Future<void> updateOpeningHoursOnMerge(
    int landmarkId,
    Map<Weekday, List<OpeningHour>> submitted,
  ) async {
    final List<Map<String, dynamic>> storedRows = await api.selectAll(
      APIManager.tableOpeningHours,
      columns:
          'opening_hours_id, day, status, opening_time, closing_time, '
          'landmark_id, restaurant_id',
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
    final Map<Weekday, List<OpeningHour>> storedByDay =
        <Weekday, List<OpeningHour>>{};
    for (final Map<String, dynamic> row in storedRows) {
      final OpeningHour? hour = _toOpeningHour(row);
      if (hour == null) continue;
      storedByDay.putIfAbsent(hour.day, () => <OpeningHour>[]).add(hour);
    }

    final Set<Weekday> changedDays = changedOpeningHourDays(
      storedByDay: storedByDay,
      submitted: submitted,
    );
    if (changedDays.isEmpty) return;
    for (final Weekday day in changedDays) {
      await api.deleteRows(
        APIManager.tableOpeningHours,
        eq: <String, Object?>{'landmark_id': landmarkId, 'day': _dayName(day)},
      );
      final List<OpeningHour> rows = submitted[day] ?? const <OpeningHour>[];
      if (rows.isEmpty) continue;
      await _insertOpeningHours(landmarkId, rows);
    }
  }

  /// Pure per-day merge decision for [updateOpeningHoursOnMerge]: given the
  /// rows already STORED per weekday and the day-rows a re-submission
  /// carries, returns the set of weekdays whose stored rows must be replaced.
  ///
  /// A weekday is "changed" only when the re-submission asserts a definitive
  /// answer for it (at least one Open/Closed row - i.e. NOT left in the
  /// form's default Unknown state) AND that asserted schedule differs from
  /// what is stored. Unknown-only days and identical days are never
  /// rewritten - the same "never clobber richer data with an emptier
  /// re-submission" rule the contact fields follow (see
  /// [changedContactFields]).
  static Set<Weekday> changedOpeningHourDays({
    required Map<Weekday, List<OpeningHour>> storedByDay,
    required Map<Weekday, List<OpeningHour>> submitted,
  }) {
    final Set<Weekday> changed = <Weekday>{};
    for (final Weekday day in Weekday.values) {
      final List<OpeningHour> incoming =
          submitted[day] ?? const <OpeningHour>[];
      final bool asserted = incoming.any(
        (OpeningHour hour) => hour.status != DayStatus.unknown,
      );
      if (!asserted) continue;
      final List<OpeningHour> stored =
          storedByDay[day] ?? const <OpeningHour>[];
      if (!_sameDayHours(stored, incoming)) changed.add(day);
    }
    return changed;
  }

  /// Whether two days' hour rows are semantically identical - the same set of
  /// (status, opensAt, closesAt) rows regardless of order or row ids. A day
  /// whose stored rows exactly match the submission's rows is a no-op and is
  /// not rewritten.
  static bool _sameDayHours(List<OpeningHour> a, List<OpeningHour> b) {
    final List<String> keyA = <String>[
      for (final OpeningHour hour in a)
        '${hour.status.name}|${hour.opensAt}|${hour.closesAt}',
    ]..sort();
    final List<String> keyB = <String>[
      for (final OpeningHour hour in b)
        '${hour.status.name}|${hour.opensAt}|${hour.closesAt}',
    ]..sort();
    if (keyA.length != keyB.length) return false;
    for (int i = 0; i < keyA.length; i++) {
      if (keyA[i] != keyB[i]) return false;
    }
    return true;
  }

  /// A13: attach new item(s) to an existing [landmarkId] - e.g. an extra dish
  /// added to a landmark that already exists. `landmark_item_id` is identity,
  /// so the DB assigns it.
  Future<void> addItems(int landmarkId, List<LandmarkItem> items) async {
    for (final LandmarkItem item in items) {
      // Test/QA data ("fake food") has no dedicated column in `landmark_item`
      // (following the real Supabase design), so the marker is written into
      // the saved dish text so the row is clearly identifiable in the DB.
      final String dish = item.isFake ? '[FAKE] ${item.dish}' : item.dish;
      await api.insertRow(APIManager.tableLandmarkItem, <String, dynamic>{
        'landmark_id': landmarkId,
        'tourist_id': item.touristId,
        // The curated dish this item resolves to; null when it is not in the
        // catalogue yet (a brand-new food - backfilled after Option-C).
        'local_food_id': item.localFoodId > 0 ? item.localFoodId : null,
        'dish': dish,
        'variant': item.variant,
        'food_category': item.foodCategory,
        'description': item.description,
        'origin': item.origin,
        'cultural_background': item.culturalBackground,
        // The variant's own observed facts (see `LandmarkItem.ingredients`
        // / `dietaryRestrictions`) - null when there is nothing to record.
        'ingredients': item.ingredients.trim().isEmpty
            ? null
            : item.ingredients,
        'dietary_restrictions': item.dietaryRestrictions.isEmpty
            ? null
            : item.dietaryRestrictions.join(', '),
        'image_url': item.imageUrl,
        'image_id': item.imageId,
        'item_price': item.price,
        'price_min': item.priceMin > 0 ? item.priceMin : null,
        'price_max': item.priceMax > 0 ? item.priceMax : null,
        'seasonal': item.seasonal,
        'cooking_style': item.cookingStyle,
        'meal_type': item.mealType,
      });
    }
  }

  /// Option C backfill: points the item(s) of [landmarkId] whose `dish` text
  /// equals [dishName] at [localFoodId]. The item was saved before its
  /// brand-new `local_food` row existed, so `local_food_id` was null; this
  /// fills it in now that the id is known. `dish` was written verbatim from
  /// the recognized food name, so an exact equality filter is the match.
  Future<void> linkItemToFood(
    int landmarkId,
    String dishName,
    int localFoodId,
  ) async {
    await api.updateRow(
      APIManager.tableLandmarkItem,
      <String, Object?>{'local_food_id': localFoodId},
      eq: <String, Object?>{'landmark_id': landmarkId, 'dish': dishName},
    );
  }

  /// A20: reactivate a frozen landmark - sets its `status` back to
  /// [LandmarkStatus.available] so it is re-queued for display.
  Future<void> reactivate(int landmarkId) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'status': LandmarkStatus.available.name},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// A tourist just re-confirmed (in person, within ~100m) that this place
  /// exists, so an older submission of the same place is reactivated AND
  /// cleaned: `reported_count` -> 0 and `status` -> 'available'. Used by the
  /// Add-Landmark merge/dedupe flow on any existing submitted landmark that
  /// matches the new submission's restaurant name + location.
  Future<void> clearReportsAndReactivate(int landmarkId) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{
        'reported_count': 0,
        'status': LandmarkStatus.available.name,
      },
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// Increments `submitted_landmark.reported_count` by one after a report is
  /// recorded and returns the new value (read-modify-write - fine at the
  /// current dev scale; a later authenticated RPC can make it atomic).
  Future<int> incrementReportCount(int landmarkId) async {
    final Map<String, dynamic>? row = await api.selectOne(
      APIManager.tableSubmittedLandmark,
      columns: 'reported_count',
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
    final int next = ((row?['reported_count'] as num?)?.toInt() ?? 0) + 1;
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'reported_count': next},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
    return next;
  }

  /// Freezes a landmark (`status` -> 'frozen') once its report count passes
  /// the threshold - the map/search/list filters only show 'available'
  /// places, so a frozen landmark disappears from discovery until it is
  /// reactivated (A20 / [reactivate]).
  Future<void> freeze(int landmarkId) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'status': 'frozen'},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  // ===========================================================================
  // Report auto-apply writes (REPORT_REDESIGN_PLAN.md) - called when a claim
  // reaches its threshold. Each is a single targeted UPDATE.
  // ===========================================================================

  /// 2a item_price: rewrites one submitted dish's price to the reported
  /// value (`landmark_item.item_price`).
  Future<void> updateLandmarkItemPrice(int itemId, double price) async {
    await api.updateRow(
      APIManager.tableLandmarkItem,
      <String, Object?>{'item_price': price},
      eq: <String, Object?>{'landmark_item_id': itemId},
    );
  }

  /// 2b item_not_exist: soft-removes one submitted dish (`is_removed`),
  /// hiding it from the place's detail without deleting the row.
  Future<void> softRemoveLandmarkItem(int itemId) async {
    await api.updateRow(
      APIManager.tableLandmarkItem,
      <String, Object?>{'is_removed': true},
      eq: <String, Object?>{'landmark_item_id': itemId},
    );
  }

  /// 2b: how many of [landmarkId]'s dishes are still shown (not removed) -
  /// used to decide whether the whole landmark should be hidden when every
  /// dish was reported not-exist.
  Future<int> countVisibleLandmarkItems(int landmarkId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableLandmarkItem,
      columns: 'landmark_item_id',
      eq: <String, Object?>{'landmark_id': landmarkId, 'is_removed': false},
    );
    return rows.length;
  }

  /// 2b: hides a landmark whose every dish was reported not-exist
  /// (`status` -> 'removed' - distinct from report-freeze 'frozen').
  Future<void> removeLandmark(int landmarkId) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'status': 'removed'},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// 3 address: rewrites the landmark's address to the reported value.
  Future<void> updateLandmarkAddress(int landmarkId, String address) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'address': address},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// 4a closed permanently / 4b closed temporarily: freezes the landmark.
  /// For a TEMPORARY closure the caller sets [closedUntil] so the place can
  /// auto-reactivate once that time passes (see [reactivateFromClosure]).
  Future<void> freezeLandmark(int landmarkId, {DateTime? closedUntil}) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{
        'status': 'frozen',
        if (closedUntil != null) 'closed_until': closedUntil.toUtc(),
      },
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// 4b resume: clears a temporary closure that has expired - back to
  /// 'available' with no `closed_until`.
  Future<void> reactivateLandmarkFromClosure(int landmarkId) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'status': 'available', 'closed_until': null},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
  }

  /// 1 operating hours: replaces ONE weekday's stored rows with the reported
  /// proposal (delete that day's rows, insert the proposed rows). Used when a
  /// day's hours claim reaches its threshold - only that day is touched.
  Future<void> replaceLandmarkOpeningHourDay(
    int landmarkId,
    Weekday day,
    List<OpeningHour> rows,
  ) async {
    await api.deleteRows(
      APIManager.tableOpeningHours,
      eq: <String, Object?>{'landmark_id': landmarkId, 'day': _dayName(day)},
    );
    if (rows.isEmpty) return;
    await _insertOpeningHours(landmarkId, rows);
  }

  /// Every submitted landmark whose name equals [name] (trimmed,
  /// case-insensitive). Lightweight rows (no dishes/opening hours) - the
  /// submit flow only needs id + coordinates to decide which previously
  /// submitted landmarks belong to the same place (~100m) and should be
  /// reactivated/cleared.
  Future<List<SubmittedLandmark>> findByName(String name) async {
    final String normalized = placeNameKey(name);
    if (normalized.isEmpty) return const <SubmittedLandmark>[];
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableSubmittedLandmark,
      columns:
          'landmark_id, landmark_name, latitude, longitude, reported_count, '
          'status',
    );
    final List<SubmittedLandmark> matches = <SubmittedLandmark>[];
    for (final Map<String, dynamic> row in rows) {
      final String rowName = placeNameKey(
        row['landmark_name'] as String? ?? '',
      );
      if (rowName != normalized) continue;
      matches.add(
        SubmittedLandmark(
          id: (row['landmark_id'] as num).toInt(),
          name: row['landmark_name'] as String? ?? '',
          latitude: (row['latitude'] as num?)?.toDouble(),
          longitude: (row['longitude'] as num?)?.toDouble(),
          category: '',
          reportedCount: (row['reported_count'] as num?)?.toInt() ?? 0,
          status:
              (row['status'] as String? ?? '').toLowerCase() ==
                  LandmarkStatus.frozen.name
              ? LandmarkStatus.frozen
              : LandmarkStatus.available,
          items: const <LandmarkItem>[],
          openingHours: const <OpeningHour>[],
        ),
      );
    }
    return matches;
  }

  /// Reads ONE submitted landmark with everything its detail screen needs:
  /// the `submitted_landmark` row, its `landmark_item` dishes and its
  /// `opening_hours`. Returns null when no such landmark exists. Rows are
  /// parsed by their data models and composed into the domain
  /// `SubmittedLandmark` here - the repository's one job (see class doc).
  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) async {
    final Map<String, dynamic>? landmarkRow;
    final List<Map<String, dynamic>> itemRows;
    final List<Map<String, dynamic>> hourRows;
    try {
      final List<Object?> results = await Future.wait(<Future<Object?>>[
        api.selectOne(
          APIManager.tableSubmittedLandmark,
          columns:
              'landmark_id, landmark_name, longitude, latitude, category, '
              'reported_count, status, image_url, image_id, image_category, '
              'phone, website, address',
          eq: <String, Object?>{'landmark_id': landmarkId},
        ),
        api.selectAll(
          APIManager.tableLandmarkItem,
          eq: <String, Object?>{'landmark_id': landmarkId},
          orderBy: 'landmark_item_id',
        ),
        api.selectAll(
          APIManager.tableOpeningHours,
          columns:
              'opening_hours_id, day, status, opening_time, closing_time, '
              'landmark_id, restaurant_id',
          eq: <String, Object?>{'landmark_id': landmarkId},
        ),
      ]);
      landmarkRow = results[0] as Map<String, dynamic>?;
      itemRows = results[1] as List<Map<String, dynamic>>;
      hourRows = results[2] as List<Map<String, dynamic>>;
    } catch (error, stackTrace) {
      developer.log(
        'Submitted-landmark detail query failed.',
        name: 'SubmittedLandmarkRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load this landmark. Check your connection and try again.',
      );
    }
    if (landmarkRow == null) return null;
    return _toDomain(landmarkRow, itemRows, hourRows);
  }

  /// The landmark's CURRENT dishes for the report page's item picker -
  /// lightweight rows (id + dish + price), excluding items already
  /// soft-removed by earlier reports. A tourist can only report a price /
  /// existence of a dish the place is still showing.
  Future<List<LandmarkItem>> getReportableItems(int landmarkId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableLandmarkItem,
      columns:
          'landmark_item_id, landmark_id, tourist_id, local_food_id, '
          'dish, item_price',
      eq: <String, Object?>{'landmark_id': landmarkId, 'is_removed': false},
      orderBy: 'landmark_item_id',
    );
    return List<LandmarkItem>.unmodifiable(
      rows.map(
        (Map<String, dynamic> row) =>
            _toItem(LandmarkItemDataModel.fromJson(row)),
      ),
    );
  }

  /// `submitted_landmark` + `landmark_item` + `opening_hours` rows -> the
  /// `SubmittedLandmark` domain model. Each table is parsed by its own data
  /// model before composition.
  SubmittedLandmark _toDomain(
    Map<String, dynamic> landmarkRow,
    List<Map<String, dynamic>> itemRows,
    List<Map<String, dynamic>> hourRows,
  ) {
    final SubmittedLandmarkDataModel landmark =
        SubmittedLandmarkDataModel.fromJson(landmarkRow);
    final List<LandmarkItem> items = <LandmarkItem>[
      for (final Map<String, dynamic> itemRow in itemRows)
        _toItem(LandmarkItemDataModel.fromJson(itemRow)),
    ];
    final List<OpeningHour> hours = <OpeningHour>[
      for (final Map<String, dynamic> hourRow in hourRows)
        if (_toOpeningHour(hourRow) case final OpeningHour hour) hour,
    ];
    return SubmittedLandmark(
      id: landmark.landmarkId,
      name: landmark.landmarkName ?? '',
      latitude: landmark.latitude,
      longitude: landmark.longitude,
      category: landmark.category ?? '',
      reportedCount: landmark.reportedCount,
      status: landmark.status?.toLowerCase() == LandmarkStatus.frozen.name
          ? LandmarkStatus.frozen
          : LandmarkStatus.available,
      imageUrl: landmark.imageUrl,
      imageId: landmark.imageId,
      imageCategory: landmark.imageCategory,
      phone: landmark.phone ?? '',
      website: landmark.website ?? '',
      address: landmark.address ?? '',
      items: items,
      openingHours: hours,
    );
  }

  /// `landmark_item` row -> `LandmarkItem`. The `[FAKE]` test marker written
  /// by [addItems] is stripped back into [LandmarkItem.isFake].
  LandmarkItem _toItem(LandmarkItemDataModel data) {
    final String dish = data.dish ?? '';
    final bool fake = dish.startsWith('[FAKE] ');
    return LandmarkItem(
      id: data.landmarkItemId,
      landmarkId: data.landmarkId,
      touristId: data.touristId,
      localFoodId: data.localFoodId ?? 0,
      dish: fake ? dish.substring('[FAKE] '.length) : dish,
      variant: data.variant ?? '',
      foodCategory: data.foodCategory ?? '',
      description: data.description ?? '',
      origin: data.origin ?? '',
      culturalBackground: data.culturalBackground ?? '',
      ingredients: data.ingredients ?? '',
      dietaryRestrictions: _splitRestrictions(data.dietaryRestrictions),
      imageUrl: data.imageUrl,
      imageId: data.imageId,
      price: data.itemPrice,
      priceMin: data.priceMin ?? 0,
      priceMax: data.priceMax ?? 0,
      seasonal: data.seasonal ?? '',
      cookingStyle: data.cookingStyle ?? '',
      mealType: data.mealType ?? '',
      isRemoved: data.isRemoved,
      isFake: fake,
    );
  }

  /// Splits the comma-separated `landmark_item.dietary_restrictions` text
  /// back into canonical restriction names. Null / empty -> empty list.
  static List<String> _splitRestrictions(String? text) {
    if (text == null) return const <String>[];
    return List<String>.unmodifiable(
      text
          .split(',')
          .map((String name) => name.trim())
          .where((String name) => name.isNotEmpty),
    );
  }

  /// `opening_hours` row -> `OpeningHour`. Returns null when its enum text
  /// does not match the ERD values.
  OpeningHour? _toOpeningHour(Map<String, dynamic> row) {
    final OpeningHoursDataModel data = OpeningHoursDataModel.fromJson(row);
    final Weekday? day = _weekday(data.day);
    final DayStatus? status = _dayStatus(data.status);
    if (day == null || status == null) return null;
    final int? opensAt = _minutesOfDay(data.openingTime);
    int? closesAt = _minutesOfDay(data.closingTime);
    if (status == DayStatus.open &&
        opensAt == 0 &&
        data.closingTime?.startsWith('23:59') == true) {
      closesAt = 1440;
    }
    return OpeningHour(
      id: data.openingHoursId,
      day: day,
      status: status,
      opensAt: status == DayStatus.open ? opensAt : null,
      closesAt: status == DayStatus.open ? closesAt : null,
    );
  }

  static Weekday? _weekday(String value) {
    final String name = value.trim().toLowerCase();
    for (final Weekday day in Weekday.values) {
      if (day.name == name) return day;
    }
    return null;
  }

  static DayStatus? _dayStatus(String value) {
    final String name = value.trim().toLowerCase();
    for (final DayStatus status in DayStatus.values) {
      if (status.name == name) return status;
    }
    return null;
  }

  /// `"HH:MM:SS"` -> minutes since midnight.
  static int? _minutesOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final List<String> parts = value.split(':');
    if (parts.length < 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Every submitted landmark this tourist has contributed dishes to, newest
  /// first. `submitted_landmark` itself has no contributor column - the
  /// contributor is recorded per dish on `landmark_item.tourist_id` - so a
  /// landmark counts as "theirs" when at least one of its dishes carries
  /// their id. Each landmark carries its dishes so a list tile can show
  /// counts/names; opening hours are left to the detail screen
  /// ([getSubmittedLandmarkById]), which fetches them on demand.
  ///
  /// One tourist can contribute to MANY landmarks, so the queries are bounded
  /// to their rows (via `tourist_id` then an `in` filter) - never "all
  /// submitted landmarks".
  Future<List<SubmittedLandmark>> getSubmittedLandmarksByTourist(
    String touristId,
  ) async {
    try {
      final List<Map<String, dynamic>> mine = await api.selectAll(
        APIManager.tableLandmarkItem,
        columns: 'landmark_id',
        eq: <String, Object?>{'tourist_id': touristId},
      );
      if (mine.isEmpty) return const <SubmittedLandmark>[];
      final Set<int> ids = <int>{
        for (final Map<String, dynamic> row in mine)
          if (JsonReader.asInt(row['landmark_id']) != 0)
            JsonReader.asInt(row['landmark_id']),
      };
      if (ids.isEmpty) return const <SubmittedLandmark>[];
      final List<int> idList = ids.toList();

      final List<Map<String, dynamic>> landmarkRows = await api.selectAll(
        APIManager.tableSubmittedLandmark,
        columns:
            'landmark_id, landmark_name, longitude, latitude, category, '
            'reported_count, status, image_url, image_id, image_category',
        inFilter: <String, List<Object?>>{'landmark_id': idList},
        orderBy: 'landmark_id',
        ascending: false,
      );
      final List<Map<String, dynamic>> itemRows = await api.selectAll(
        APIManager.tableLandmarkItem,
        inFilter: <String, List<Object?>>{'landmark_id': idList},
        orderBy: 'landmark_item_id',
      );

      // Group each landmark's dish rows so _toDomain composes them per row.
      final Map<int, List<Map<String, dynamic>>> itemRowsById =
          <int, List<Map<String, dynamic>>>{};
      for (final Map<String, dynamic> row in itemRows) {
        final int landmarkId = JsonReader.asInt(row['landmark_id']);
        itemRowsById
            .putIfAbsent(landmarkId, () => <Map<String, dynamic>>[])
            .add(row);
      }

      return <SubmittedLandmark>[
        for (final Map<String, dynamic> landmarkRow in landmarkRows)
          _toDomain(
            landmarkRow,
            itemRowsById[JsonReader.asInt(landmarkRow['landmark_id'])] ??
                const <Map<String, dynamic>>[],
            const <Map<String, dynamic>>[], // hours: detail screen fetches them
          ),
      ];
    } catch (error, stackTrace) {
      developer.log(
        'Submitted-landmark history query failed.',
        name: 'SubmittedLandmarkRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load your submitted landmarks. '
        'Check your connection and try again.',
      );
    }
  }

  /// Uploads a captured photo - a food's own photo, OR the landmark's
  /// signboard/stall photo - to Supabase Storage (`landmark-images` bucket)
  /// and returns what the row stores for it:
  ///   * [id] - the storage object name (`landmark_item.image_id` /
  ///     `submitted_landmark.image_id`);
  ///   * [url] - its public HTTPS URL (`landmark_item.image_url` /
  ///     `submitted_landmark.image_url`).
  /// Only called when a photo actually exists - see
  /// `AddLandmarkViewModel.submitLandmark`, which skips this when there's no
  /// image (e.g. a name-typed food with no photo).
  Future<({String id, String url})> uploadImage(List<int> bytes) async {
    // Unique object name per upload - a tourist photo is never overwritten.
    final String objectName =
        'photo/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final String path = await api.uploadLandmarkImage(
      bytes: bytes,
      path: objectName,
    );
    // The object key the SDK returns should be the bare path we sent. Guard
    // against SDKs that return it already prefixed with the bucket name - if
    // that prefix leaked into the public URL the path would double the bucket
    // segment (".../public/landmark-images/landmark-images/photo/...") and
    // Supabase would answer 404 NoSuchKey, which is exactly the blank-card
    // symptom. Stripping it is a no-op when the key was already bare.
    final String objectKey =
        path.startsWith('${APIManager.storageBucketLandmarkImages}/')
        ? path.substring(APIManager.storageBucketLandmarkImages.length + 1)
        : path;
    final String? url = api.resolveImageUrl(
      objectKey,
      bucket: APIManager.storageBucketLandmarkImages,
    );
    return (id: objectKey, url: url ?? '');
  }

  Future<void> _insertOpeningHours(
    int landmarkId,
    List<OpeningHour> hours,
  ) async {
    int nextId = await _nextId(
      APIManager.tableOpeningHours,
      'opening_hours_id',
    );
    for (final OpeningHour hour in hours) {
      final bool isOpen = hour.status == DayStatus.open;
      await api.insertRow(APIManager.tableOpeningHours, <String, dynamic>{
        'opening_hours_id': nextId++,
        'day': _dayName(hour.day),
        'status': hour.status.name,
        'opening_time': isOpen && hour.opensAt != null
            ? _formatTime(hour.opensAt!)
            : null,
        'closing_time': isOpen && hour.closesAt != null
            ? _formatTime(hour.closesAt!)
            : null,
        'landmark_id': landmarkId,
        'restaurant_id': null,
      });
    }
  }

  /// Next value for a non-identity integer PK (max + 1). Returns 1 when the
  /// table is empty (or reads are denied by RLS).
  Future<int> _nextId(String table, String column) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      table,
      columns: column,
      orderBy: column,
      ascending: false,
      limit: 1,
    );
    if (rows.isEmpty) return 1;
    return ((rows.first[column] as num?)?.toInt() ?? 0) + 1;
  }

  static String _dayName(Weekday day) => switch (day) {
    Weekday.monday => 'Monday',
    Weekday.tuesday => 'Tuesday',
    Weekday.wednesday => 'Wednesday',
    Weekday.thursday => 'Thursday',
    Weekday.friday => 'Friday',
    Weekday.saturday => 'Saturday',
    Weekday.sunday => 'Sunday',
  };

  /// Minutes since midnight (0-1440, where 1440 = "24:00") to the Postgres
  /// `time` wire string `"HH:MM:SS"`.
  static String _formatTime(int minutes) {
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${mins.toString().padLeft(2, '0')}:00';
  }
}
