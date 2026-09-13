import 'auth_repository.dart';
import 'geocoding_repository.dart';
import 'landmark_draft_repository.dart';
import 'link_check_repository.dart';
import 'location_repository.dart';
import 'map_repository.dart';
import 'recognition_repository.dart';
import 'report_repository.dart';
import 'restaurant_repository.dart';
import 'submitted_landmark_repository.dart';

/// Everything about places the tourist contributes and explores: submitted
/// landmarks, the restaurant behind them, the map viewport and the device
/// location.
///
/// `restaurant`, `recognition` and `auth` are also reachable through their
/// usual facades (`DiscoveryRepositoryFacade`, `TouristRepositoryFacade`) -
/// each facade holds its own reference to the same underlying `APIManager`,
/// so this is a second door to the same data, not a duplicate source.
/// `LandmarkSubmissionLogic` needs all three here directly: it checks
/// whether a restaurant already exists (A13), analyses the signboard/stall
/// photo, and resolves who is submitting (`LandmarkItem.touristId`) - and
/// per the guideline a logic class holds only ONE repository facade.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not six
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class LandmarkRepositoryFacade {
  LandmarkRepositoryFacade();

  final SubmittedLandmarkRepository landmark = SubmittedLandmarkRepository();
  final MapRepository map = MapRepository();
  final LocationRepository location = LocationRepository();
  final RestaurantRepository restaurant = RestaurantRepository();
  final RecognitionRepository recognition = RecognitionRepository();
  final AuthRepository auth = AuthRepository();

  /// Shared tourist report table (kind + place_id + reason).
  final ReportRepository report = ReportRepository();

  /// Website reachability checks for the Add-Landmark website field.
  final LinkCheckRepository links = LinkCheckRepository();

  /// OpenStreetMap geocoding for the Add-Landmark address field (suggestions)
  /// and the composed address behind the map pin.
  final GeocodingRepository geocoding = GeocodingRepository();

  /// Saved (incomplete) Add-New-Landmark forms.
  final LandmarkDraftRepository drafts = LandmarkDraftRepository();
}
