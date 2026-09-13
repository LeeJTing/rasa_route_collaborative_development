import '../../core/json_model.dart';

/// JSON shape persisted by `TutorialRepository` for the walkthrough.
///
/// One small record under a single key. It is written twice in a tourist's
/// life - once when they finish or skip the tutorial, and once again a year
/// later - so nothing here needs to be cheap to parse, only impossible to
/// misread.
class TutorialProgressDataModel implements JsonModel {
  const TutorialProgressDataModel({
    required this.completed,
    required this.shownAt,
    required this.version,
  });

  final bool completed;
  final DateTime? shownAt;
  final int version;

  factory TutorialProgressDataModel.fromJson(Map<String, dynamic> json) =>
      TutorialProgressDataModel(
        completed: JsonReader.asBool(json['completed']),
        shownAt: JsonReader.asDateOrNull(json['shown_at']),
        version: JsonReader.asInt(json['version']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'completed': completed,
    'shown_at': shownAt?.toIso8601String(),
    'version': version,
  };
}
