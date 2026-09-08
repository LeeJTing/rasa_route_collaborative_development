/// Why a tourist is reporting a submitted-landmark pin. Mirrors the
/// catalogue's `RestaurantReportReason` (the report feature was first built
/// for normal restaurant detail, and is now also offered on submitted
/// landmark pins) - reasons phrased for a tourist-submitted restaurant.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is
/// what converts a data model into one of these.
enum LandmarkReportReason {
  noLongerExists,
  incorrectName,
  incorrectLocation,
  incorrectOperatingHours,
  incorrectInformation,
}
