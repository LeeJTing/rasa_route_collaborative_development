/// How much map data exists right now.
///
/// A cheap signature `RestaurantMonitor` polls to notice that *somebody else*
/// added a landmark. Comparing two stamps is how the app knows the map a
/// tourist is looking at has fallen behind the database.
///
/// Counts rather than timestamps: neither `submitted_landmark` nor `restaurant`
/// carries a `created_at`, and counting ids is one small column to read.
/// The trade-off is honest and documented - a row added *and* another removed
/// between two polls leaves the count unchanged and the change is missed until
/// the next real one. For "a new landmark appeared", that is fine.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these.
class MapDataStamp {
  const MapDataStamp({
    required this.landmarkCount,
    required this.restaurantCount,
  });

  static const MapDataStamp empty = MapDataStamp(
    landmarkCount: 0,
    restaurantCount: 0,
  );

  final int landmarkCount;
  final int restaurantCount;
}
