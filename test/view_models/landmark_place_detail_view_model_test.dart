import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/landmark_report_reason.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/landmark_place_detail_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records a new landmark report and exposes feedback state', () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade();
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(3);

    expect(viewModel.reportSubmitted, isFalse);

    await viewModel.submitReport(LandmarkReportReason.incorrectLocation);
    expect(viewModel.reportSubmitted, isTrue);
    expect(viewModel.alreadyReported, isFalse);
    expect(viewModel.reportFailed, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.reportSubmitted, isFalse);
    expect(viewModel.alreadyReported, isFalse);
    expect(viewModel.reportFailed, isFalse);

    viewModel.dispose();
  });

  test('flags a duplicate landmark report without counting it again', () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade(
      duplicate: true,
    );
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(3);

    await viewModel.submitReport(LandmarkReportReason.incorrectName);
    expect(viewModel.alreadyReported, isTrue);
    expect(viewModel.reportSubmitted, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.alreadyReported, isFalse);

    viewModel.dispose();
  });

  test('flags a backend failure instead of confirming the report', () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade(
      fail: true,
    );
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(3);

    await viewModel.submitReport(LandmarkReportReason.noLongerExists);
    expect(viewModel.reportFailed, isTrue);
    expect(viewModel.reportSubmitted, isFalse);
    expect(viewModel.alreadyReported, isFalse);

    viewModel.dispose();
  });

  test('asks a signed-out tourist to sign in before counting a report',
      () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade(
      requireSignIn: true,
    );
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(3);

    await viewModel.submitReport(LandmarkReportReason.incorrectLocation);
    expect(viewModel.requiresSignIn, isTrue);
    expect(viewModel.reportSubmitted, isFalse);
    expect(viewModel.alreadyReported, isFalse);
    expect(viewModel.reportFailed, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.requiresSignIn, isFalse);

    viewModel.dispose();
  });

  test('flags when the report froze the landmark so the View leaves the map',
      () async {
    final _FakeLandmarkLogicFacade logic = _FakeLandmarkLogicFacade(
      frozePlace: true,
    );
    final LandmarkPlaceDetailViewModel viewModel =
        _TestLandmarkPlaceDetailViewModel(logic);
    viewModel.setLandmarkId(3);

    await viewModel.submitReport(LandmarkReportReason.incorrectLocation);
    expect(viewModel.reportSubmitted, isTrue);
    expect(viewModel.reportFrozePlace, isTrue);
    expect(viewModel.alreadyReported, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.reportFrozePlace, isFalse);
    expect(viewModel.reportSubmitted, isFalse);

    viewModel.dispose();
  });
}

class _TestLandmarkPlaceDetailViewModel extends LandmarkPlaceDetailViewModel {
  _TestLandmarkPlaceDetailViewModel(this.logic);

  final LandmarkLogicFacade logic;

  @override
  LandmarkLogicFacade createLandmarkLogic() => logic;
}

class _FakeLandmarkLogicFacade extends LandmarkLogicFacade {
  _FakeLandmarkLogicFacade({
    this.duplicate = false,
    this.fail = false,
    this.requireSignIn = false,
    this.frozePlace = false,
  });

  final bool duplicate;
  final bool fail;
  final bool requireSignIn;
  final bool frozePlace;

  @override
  Future<({bool requiresSignIn, bool alreadyReported, bool frozePlace})>
      submitLandmarkReport({
    required int landmarkId,
    required LandmarkReportReason reason,
    String? touristId,
  }) async {
    if (fail) throw Exception('Could not reach the report service.');
    if (requireSignIn) {
      return (
        requiresSignIn: true,
        alreadyReported: false,
        frozePlace: false,
      );
    }
    if (frozePlace) {
      return (
        requiresSignIn: false,
        alreadyReported: false,
        frozePlace: true,
      );
    }
    return (
      requiresSignIn: false,
      alreadyReported: duplicate,
      frozePlace: false,
    );
  }
}
