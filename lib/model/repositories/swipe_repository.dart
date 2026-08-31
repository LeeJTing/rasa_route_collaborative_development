import '../../domain_model/swipe_session.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';
import '../data_models/swipe_session_data_model.dart';

/// The swipe-to-discover deck.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class SwipeRepository {
  SwipeRepository();

  final LocalStorageManager storage = LocalStorageManager();

  Future<SwipeSession?> getSession({
    required String touristId,
    required String stateCode,
  }) async {
    final Map<String, dynamic>? json = storage.readJson(
      _sessionKey(touristId, stateCode),
    );
    if (json == null) return null;
    final SwipeSessionDataModel data = SwipeSessionDataModel.fromJson(json);
    final SwipeSession session = _toDomain(data);
    if (session.touristId != touristId || session.stateCode != stateCode) {
      return null;
    }
    return session;
  }

  Future<void> saveSession(SwipeSession session) {
    final SwipeSessionDataModel data = _toDataModel(session);
    return storage.writeJson(
      _sessionKey(session.touristId, session.stateCode),
      data.toJson(),
    );
  }

  Future<void> deleteSession({
    required String touristId,
    required String stateCode,
  }) => storage.remove(_sessionKey(touristId, stateCode));

  String _sessionKey(String touristId, String stateCode) =>
      '${LocalStorageManager.keyActiveSwipeSession}:$touristId:$stateCode';

  SwipeSessionDataModel _toDataModel(SwipeSession session) =>
      SwipeSessionDataModel(
        sessionId: session.sessionId,
        touristId: session.touristId,
        stateCode: session.stateCode,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
        candidateFoodIds: session.candidateFoodIds,
        likedFoodIds: session.likedFoodIds,
        dislikedFoodIds: session.dislikedFoodIds,
        currentIndex: session.currentIndex,
      );

  SwipeSession _toDomain(SwipeSessionDataModel data) => SwipeSession(
    sessionId: data.sessionId,
    touristId: data.touristId,
    stateCode: data.stateCode,
    startedAt: data.startedAt,
    endedAt: data.endedAt,
    candidateFoodIds: List<int>.unmodifiable(data.candidateFoodIds),
    likedFoodIds: List<int>.unmodifiable(data.likedFoodIds),
    dislikedFoodIds: List<int>.unmodifiable(data.dislikedFoodIds),
    currentIndex: data.currentIndex,
  );
}
