import '../../domain_model/report_category.dart';
import '../../domain_model/tourist_location.dart';

/// Carries the selected place from a detail screen to the report route.
///
/// The value is consumed once, matching the app's existing route handoff
/// convention while keeping navigation state out of a ViewModel file.
class ReportPlaceHandoff {
  factory ReportPlaceHandoff() => _instance;

  ReportPlaceHandoff._();

  static final ReportPlaceHandoff _instance = ReportPlaceHandoff._();

  ReportPlaceKind? pendingKind;
  int? pendingPlaceId;
  String pendingName = '';
  TouristLocation pendingLocation = TouristLocation.unknown;

  (ReportPlaceKind, int, String, TouristLocation)? take() {
    final ReportPlaceKind? kind = pendingKind;
    final int? placeId = pendingPlaceId;
    if (kind == null || placeId == null) return null;
    final (ReportPlaceKind, int, String, TouristLocation) value = (
      kind,
      placeId,
      pendingName,
      pendingLocation,
    );
    pendingKind = null;
    pendingPlaceId = null;
    pendingName = '';
    pendingLocation = TouristLocation.unknown;
    return value;
  }
}
