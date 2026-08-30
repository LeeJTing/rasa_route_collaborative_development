import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/json_model.dart';

void main() {
  test('string lists accept Supabase comma and semicolon delimiters', () {
    expect(
      JsonReader.asStringList('Penang Hokkien Mee; Har Mee, Prawn Mee'),
      <String>['Penang Hokkien Mee', 'Har Mee', 'Prawn Mee'],
    );
  });
}
