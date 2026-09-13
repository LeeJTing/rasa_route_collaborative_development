/// What a same-place merge (UC500 A13) would REPLACE on the existing record:
/// the details that place already stores which this form would write over.
///
/// Shown to the tourist before anything is written - "Restoran Ali already
/// has a phone, an address and Monday hours - replace them with what you
/// entered?" - because the merge happens silently otherwise, and losing a
/// curated phone number to an emptier second submission is not something the
/// tourist can undo. Answering "keep" leaves the stored record completely
/// untouched (see `AddLandmarkViewModel.resolveOverwrite`).
class PlaceOverwriteReport {
  const PlaceOverwriteReport({
    required this.id,
    required this.name,
    required this.isRestaurant,
    required this.fields,
  });

  /// `restaurant_id` when [isRestaurant], else `landmark_id`.
  final int id;

  /// The existing place's own name, as stored.
  final String name;

  /// True for a catalogue restaurant, false for a submitted landmark.
  final bool isRestaurant;

  /// Human labels for the details this submission would replace, e.g.
  /// `['phone', 'address', 'Monday hours']` - already ordered the way the
  /// form presents them (contact details, then location, then hours).
  final List<String> fields;

  /// "phone, address and Monday hours" - the list ready for a sentence.
  String get fieldsText {
    if (fields.length == 1) return fields.single;
    final String head = fields.sublist(0, fields.length - 1).join(', ');
    return '$head and ${fields.last}';
  }
}
