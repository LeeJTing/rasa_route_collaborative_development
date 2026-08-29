import '../../core/json_model.dart';

/// JSON shape persisted by [SwipeRepository] for one state-scoped session.
class SwipeSessionDataModel implements JsonModel {
  const SwipeSessionDataModel({
    required this.sessionId,
    required this.touristId,
    required this.stateCode,
    required this.startedAt,
    this.endedAt,
    required this.candidateFoodIds,
    required this.likedFoodIds,
    required this.dislikedFoodIds,
    required this.currentIndex,
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

  factory SwipeSessionDataModel.fromJson(Map<String, dynamic> json) =>
      SwipeSessionDataModel(
        sessionId: JsonReader.asString(json['session_id']),
        touristId: JsonReader.asString(json['tourist_id']),
        stateCode: JsonReader.asString(json['state_code']),
        startedAt: JsonReader.asDateOrNull(json['started_at']),
        endedAt: JsonReader.asDateOrNull(json['ended_at']),
        candidateFoodIds: _intList(json['candidate_food_ids']),
        likedFoodIds: _intList(json['liked_food_ids']),
        dislikedFoodIds: _intList(json['disliked_food_ids']),
        currentIndex: JsonReader.asInt(json['current_index']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'session_id': sessionId,
    'tourist_id': touristId,
    'state_code': stateCode,
    'started_at': startedAt?.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'candidate_food_ids': candidateFoodIds,
    'liked_food_ids': likedFoodIds,
    'disliked_food_ids': dislikedFoodIds,
    'current_index': currentIndex,
  };

  static List<int> _intList(Object? raw) {
    if (raw is! List) return const <int>[];
    return raw
        .map(JsonReader.asIntOrNull)
        .whereType<int>()
        .toList(growable: false);
  }
}
