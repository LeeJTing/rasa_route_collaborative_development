/// A tracked tourist action - the raw signal recommendations are built from.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class Interaction {
  const Interaction({
    required this.id,
    required this.touristId,
    required this.targetType,
    required this.targetId,
    required this.action,
    this.occurredAt,
  });

  final String id;
  final String touristId;
  final InteractionTarget targetType;
  final String targetId;
  final InteractionAction action;
  final DateTime? occurredAt;
}

enum InteractionTarget { food, restaurant, landmark }

enum InteractionAction { view, like, dislike, favourite, unfavourite, share }
