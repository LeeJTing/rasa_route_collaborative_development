import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_colors.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';
import 'package:rasa_route_collaborative_development/views/landmark_place_detail_view/widgets/landmark_information_section.dart';

SubmittedLandmark _landmark({
  String address = '12, Jalan Bukit Bintang, Kuala Lumpur',
  String phone = '012-345 6789',
  String website = 'https://example.com',
  double? latitude = 3.1390,
  double? longitude = 101.6869,
}) => SubmittedLandmark(
  id: 7,
  name: 'Kopitiam Ali',
  latitude: latitude,
  longitude: longitude,
  category: 'Malay',
  reportedCount: 0,
  status: LandmarkStatus.available,
  phone: phone,
  website: website,
  address: address,
  items: const <LandmarkItem>[],
  openingHours: const <OpeningHour>[],
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('the address, phone and website rows are links', (
    WidgetTester tester,
  ) async {
    int addressTaps = 0;
    int phoneTaps = 0;
    int websiteTaps = 0;
    await tester.pumpWidget(
      _wrap(
        LandmarkInformationSection(
          landmark: _landmark(),
          onAddressTap: () => addressTaps++,
          onPhoneTap: () => phoneTaps++,
          onWebsiteTap: () => websiteTaps++,
        ),
      ),
    );

    // The same open-in-new marker and link styling the restaurant card gives
    // its own address / phone / website rows.
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(3));
    final Text addressLabel = tester.widget<Text>(
      find.text('12, Jalan Bukit Bintang, Kuala Lumpur'),
    );
    expect(addressLabel.style?.color, AppColors.info);
    expect(addressLabel.style?.decoration, TextDecoration.underline);

    await tester.tap(find.text('12, Jalan Bukit Bintang, Kuala Lumpur'));
    await tester.tap(find.text('012-345 6789'));
    await tester.tap(find.text('https://example.com'));

    expect(addressTaps, 1);
    expect(phoneTaps, 1);
    expect(websiteTaps, 1);
  });

  testWidgets("no address falls back to the landmark's coordinates", (
    WidgetTester tester,
  ) async {
    int addressTaps = 0;
    await tester.pumpWidget(
      _wrap(
        LandmarkInformationSection(
          landmark: _landmark(address: ''),
          onAddressTap: () => addressTaps++,
        ),
      ),
    );

    // A submitted pin always knows where it is - the coordinates stand in for
    // the address, and the row still opens the map.
    expect(find.text('3.13900, 101.68690'), findsOneWidget);
    expect(find.text('Address unavailable'), findsNothing);

    await tester.tap(find.text('3.13900, 101.68690'));

    expect(addressTaps, 1);
  });

  testWidgets('no address and no coordinates are honestly unavailable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        LandmarkInformationSection(
          landmark: _landmark(address: '', latitude: null, longitude: null),
          onAddressTap: () {},
          onPhoneTap: () {},
          onWebsiteTap: () {},
        ),
      ),
    );

    expect(find.text('Address unavailable'), findsOneWidget);

    // Nothing to open on the address row - the other two keep their markers.
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
  });

  testWidgets('an empty phone row has nothing behind it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        LandmarkInformationSection(
          landmark: _landmark(phone: ''),
          onAddressTap: () {},
          onPhoneTap: () {},
          onWebsiteTap: () {},
        ),
      ),
    );

    expect(find.text('Phone unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
  });
}
