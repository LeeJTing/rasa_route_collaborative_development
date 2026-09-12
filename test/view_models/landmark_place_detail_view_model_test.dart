import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/landmark_place_detail_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a submitted landmark by id', () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade();
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(3);

    await viewModel.load();

    expect(viewModel.landmark?.id, 3);
    expect(viewModel.landmark?.name, 'Tian Yi Kopitiam');

    viewModel.dispose();
  });

  test('surfaces a load failure', () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade(
      landmark: null,
    );
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(999);

    await viewModel.load();

    expect(viewModel.hasError, isTrue);
    expect(viewModel.landmark, isNull);

    viewModel.dispose();
  });

  test(
    'reports the distance from the current fix (restaurant-style)',
    () async {
      final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade();
      final LandmarkPlaceDetailViewModel viewModel =
          _TestLandmarkPlaceDetailViewModel(logic);
      viewModel.setLandmarkId(3);
      await viewModel.load();

      // No GPS fix yet - the header shows "Distance unavailable".
      expect(viewModel.landmarkDistanceMetres, isNull);

      // ~55.6 m north of the landmark's own coordinates (3.1390, 101.6869).
      viewModel.onCurrentLocationChanged(
        const TouristLocation(latitude: 3.1395, longitude: 101.6869),
      );
      expect(viewModel.landmarkDistanceMetres, closeTo(55.6, 1.0));

      // Losing the fix must take the distance away again, not freeze it.
      viewModel.onCurrentLocationChanged(TouristLocation.unknown);
      expect(viewModel.landmarkDistanceMetres, isNull);

      viewModel.dispose();
    },
  );
}

class _TestLandmarkPlaceDetailViewModel extends LandmarkPlaceDetailViewModel {
  _TestLandmarkPlaceDetailViewModel(this.logic);

  final LandmarkLogicFacade logic;

  @override
  LandmarkLogicFacade createLandmarkLogic() => logic;
}

class _FakeLandmarkLogicFacade extends LandmarkLogicFacade {
  _FakeLandmarkLogicFacade({this.landmark = _testLandmark});

  final SubmittedLandmark? landmark;

  @override
  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) async =>
      landmark?.id == landmarkId ? landmark : null;
}

const SubmittedLandmark _testLandmark = SubmittedLandmark(
  id: 3,
  name: 'Tian Yi Kopitiam',
  latitude: 3.1390,
  longitude: 101.6869,
  category: 'Kopitiam',
  reportedCount: 0,
  status: LandmarkStatus.available,
  items: <LandmarkItem>[],
  openingHours: <OpeningHour>[],
);
