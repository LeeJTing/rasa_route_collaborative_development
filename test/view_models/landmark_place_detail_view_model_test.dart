import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/view_models/landmark_place_detail_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records local report UI state for a landmark pin', () async {
    final LandmarkPlaceDetailViewModel viewModel =
        LandmarkPlaceDetailViewModel();

    expect(viewModel.reportSubmitted, isFalse);

    await viewModel.submitReport(LandmarkReportReason.incorrectLocation);
    expect(viewModel.reportSubmitted, isTrue);

    viewModel.consumeReportSubmitted();
    expect(viewModel.reportSubmitted, isFalse);

    viewModel.dispose();
  });
}
