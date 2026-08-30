/// One run of the swipe-to-discover flow.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class SwipeSession {
  const SwipeSession({
    required this.sessionId,
    required this.touristId,
    required this.stateCode,
    this.startedAt,
    this.endedAt,
    required this.candidateFoodIds,
    required this.likedFoodIds,
    required this.dislikedFoodIds,
    this.currentIndex = 0,
  });

  final String sessionId;
  final String touristId;
  final String stateCode;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<int> candidateFoodIds;
  final List<int> likedFoodIds;
  final List<int> dislikedFoodIds;
  final int currentIndex;

  SwipeSession copyWith({
    DateTime? endedAt,
    List<int>? candidateFoodIds,
    List<int>? likedFoodIds,
    List<int>? dislikedFoodIds,
    int? currentIndex,
  }) => SwipeSession(
    sessionId: sessionId,
    touristId: touristId,
    stateCode: stateCode,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    candidateFoodIds: candidateFoodIds ?? this.candidateFoodIds,
    likedFoodIds: likedFoodIds ?? this.likedFoodIds,
    dislikedFoodIds: dislikedFoodIds ?? this.dislikedFoodIds,
    currentIndex: currentIndex ?? this.currentIndex,
  );
}
