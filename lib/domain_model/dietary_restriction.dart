/// A dietary restriction a tourist can hold, such as vegetarian or no pork.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class DietaryRestriction {
  const DietaryRestriction({required this.id, required this.name});

  final int id;
  final String name;
}
