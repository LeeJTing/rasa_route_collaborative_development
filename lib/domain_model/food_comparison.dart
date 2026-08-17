/// A side-by-side comparison of two or more dishes.
/// [foodNames] is in the same order as [foodIds].
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodComparison {
  const FoodComparison({
    required this.foodIds,
    required this.foodNames,
    required this.rows,
  });

  final List<int> foodIds;
  final List<String> foodNames;
  final List<ComparisonRow> rows;
}

/// One attribute compared across every column. [values] has one entry per
/// compared dish, in the same order as `FoodComparison.foodIds`.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class ComparisonRow {
  const ComparisonRow({
    required this.attribute,
    required this.values,
    required this.isDifference,
  });

  final String attribute;
  final List<String> values;
  final bool isDifference;
}
