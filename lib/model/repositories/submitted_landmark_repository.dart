import '../../domain_model/opening_hour.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../shared_client/api_manager/api_manager.dart';

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
///     has NO `status` column: an Open day writes its times; a Closed/Unknown
///     day writes one row with null times (that's the whole representation).
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
      'reported_count': landmark.reportedCount,
      'status': landmark.status.name,
    });

    await addItems(landmarkId, landmark.items);
    await _insertOpeningHours(landmarkId, landmark.openingHours);
    return landmarkId;
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
        'dish': dish,
        'variant': item.variant,
        'food_category': item.foodCategory,
        'description': item.description,
        'origin': item.origin,
        'cultural_background': item.culturalBackground,
        'image_url': item.imageUrl,
        'image_id': item.imageId,
        'item_price': item.price,
        'seasonal': item.seasonal,
        'cooking_style': item.cookingStyle,
        'meal_type': item.mealType,
      });
    }
  }

  /// A20: reactivate a frozen landmark - sets its `status` back to `pending`
  /// so it is re-queued for moderation.
  Future<void> reactivate(int landmarkId) async {
    await api.updateRow(
      APIManager.tableSubmittedLandmark,
      <String, Object?>{'status': LandmarkStatus.pending.name},
      eq: <String, Object?>{'landmark_id': landmarkId},
    );
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
