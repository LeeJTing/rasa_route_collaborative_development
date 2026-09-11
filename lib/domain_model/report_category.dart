/// What a tourist is reporting about a place. Shared by catalogue restaurants
/// AND submitted landmarks (the report feature is identical for both kinds) -
/// replaces the old per-kind enums (`RestaurantReportReason` /
/// `LandmarkReportReason`) whose reasons were one-shot and unstructured.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is
/// what converts a data model into one of these. They travel upward unchanged
/// from repository to logic to ViewModel to View.
enum ReportCategory {
  /// One or more weekdays' opening hours are wrong. The tourist corrects the
  /// days they know; each corrected day is its own claim (threshold 10
  /// identical per day -> update that day only).
  operatingHours,

  /// One menu item's price is wrong (threshold 5 identical item+price ->
  /// update the item's price).
  itemPrice,

  /// A listed menu item does not actually exist (threshold 5 identical item ->
  /// soft-remove the item; hide the whole place when no items remain).
  itemNotExist,

  /// The place's address is wrong (threshold 5 identical text -> update).
  address,

  /// The place is closed permanently (threshold 10 -> status 'frozen').
  closedPermanently,

  /// The place is closed temporarily for a duration (threshold 10 ->
  /// freeze + `closed_until` from the most-common duration; read-time
  /// auto-reactivation once it passes).
  closedTemporarily,
}

/// The kind of menu item a claim refers to - the two item tables that mirror
/// each other (`restaurant_item` for restaurants, `landmark_item` for
/// submitted landmarks).
enum ReportItemKind {
  restaurantItem,
  landmarkItem;

  /// The `report.item_kind` column value.
  String get columnValue => switch (this) {
    ReportItemKind.restaurantItem => 'restaurant_item',
    ReportItemKind.landmarkItem => 'landmark_item',
  };

  static ReportItemKind? fromColumnValue(String? value) => switch (value) {
    'restaurant_item' => ReportItemKind.restaurantItem,
    'landmark_item' => ReportItemKind.landmarkItem,
    _ => null,
  };
}

/// The kind of place a claim refers to - `report.kind` ('restaurant' or
/// 'landmark').
enum ReportPlaceKind {
  restaurant,
  landmark;

  String get columnValue => name;

  static ReportPlaceKind? fromColumnValue(String value) => switch (value) {
    'restaurant' => ReportPlaceKind.restaurant,
    'landmark' => ReportPlaceKind.landmark,
    _ => null,
  };
}
