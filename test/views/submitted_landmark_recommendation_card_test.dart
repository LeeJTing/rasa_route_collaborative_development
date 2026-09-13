import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/app_image.dart';
import 'package:rasa_route_collaborative_development/views/matches_recommendation_view/widgets/submitted_landmark_recommendation_card.dart';

/// The Matches landmark card mirrors the restaurant card, and its PHOTO
/// keeps its own tap: it opens the full-screen viewer (the view wires
/// `showLandmarkImage`, whose note says "User submitted photo") while the
/// rest of the card opens the landmark's details - the same split the
/// quick-mode landmark card uses (user request, 2026-09-14).
void main() {
  SubmittedLandmarkRecommendation landmark({String? imageUrl}) =>
      SubmittedLandmarkRecommendation(
        id: 7,
        name: 'Warung Sepi',
        category: 'Indian',
        address: '21, Jalan Damai, 53300 Setapak, Kuala Lumpur',
        distanceMetres: 320,
        dishes: const <SubmittedLandmarkDish>[
          SubmittedLandmarkDish(name: 'Roti Canai', price: 4),
        ],
        imageUrl: imageUrl,
        price: 4,
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required VoidCallback onTap,
    required VoidCallback onImageTap,
    String? imageUrl = 'https://example.com/place.jpg',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SubmittedLandmarkRecommendationCard(
          landmark: landmark(imageUrl: imageUrl),
          onTap: onTap,
          onImageTap: onImageTap,
        ),
      ),
    ),
  );

  testWidgets('the photo opens its own viewer without opening the details', (
    WidgetTester tester,
  ) async {
    int cardTaps = 0;
    int photoTaps = 0;
    await pumpCard(
      tester,
      onTap: () => cardTaps += 1,
      onImageTap: () => photoTaps += 1,
    );

    await tester.tap(find.byType(AppImage).first);
    await tester.pump();

    expect(photoTaps, 1);
    expect(cardTaps, 0);
  });

  testWidgets('the card text opens the landmark details', (
    WidgetTester tester,
  ) async {
    int cardTaps = 0;
    int photoTaps = 0;
    await pumpCard(
      tester,
      onTap: () => cardTaps += 1,
      onImageTap: () => photoTaps += 1,
    );

    await tester.tap(find.text('Warung Sepi'));
    await tester.pump();

    expect(cardTaps, 1);
    expect(photoTaps, 0);
  });

  testWidgets('without a photo the whole card still opens the details', (
    WidgetTester tester,
  ) async {
    int cardTaps = 0;
    int photoTaps = 0;
    await pumpCard(
      tester,
      onTap: () => cardTaps += 1,
      onImageTap: () => photoTaps += 1,
      imageUrl: null,
    );

    await tester.tap(find.byType(AppImage).first);
    await tester.pump();

    expect(photoTaps, 0);
    expect(cardTaps, 1);
  });

  testWidgets('shows the address, the starting price and what it serves', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, onTap: () {}, onImageTap: () {});

    expect(
      find.text('21, Jalan Damai, 53300 Setapak, Kuala Lumpur'),
      findsOneWidget,
    );
    expect(find.text('From RM 4.00'), findsOneWidget);
    expect(find.text('Serves Roti Canai'), findsOneWidget);
    expect(find.text('320 m'), findsOneWidget);
  });
}
