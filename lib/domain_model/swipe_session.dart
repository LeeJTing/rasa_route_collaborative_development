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
    this.startedAt,
    this.endedAt,
    required this.candidateFoodIds,
    required this.likedFoodIds,
    required this.dislikedFoodIds,
  });

  final String sessionId;
  final String touristId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<int> candidateFoodIds;
  final List<int> likedFoodIds;
  final List<int> dislikedFoodIds;
}
