import '../../shared_client/api_manager/api_manager.dart';

/// Food recognition from a photo, via Gemini.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class RecognitionRepository {
  RecognitionRepository();

  final APIManager api = APIManager();
}
