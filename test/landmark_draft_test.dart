import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/landmark_draft.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/data_models/landmark_draft_data_model.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

LocalFood _food() => const LocalFood(
  id: 0,
  name: 'Nasi Lemak',
  description: 'Coconut rice',
  origin: 'Malay',
  culturalBackground: '',
  ingredients: 'rice, sambal',
  category: 'Malay',
  cookingStyle: 'Steaming',
  mealType: 'Breakfast',
  foodType: 'Food',
  tastes: <String>['Spicy'],
  mainTaste: 'Spicy',
  synonyms: <String>['Nasi Lemak Ayam'],
);

LandmarkDraft _draft({DateTime? expiresAt}) {
  final DateTime now = DateTime.now();
  return LandmarkDraft(
    id: 7,
    restaurantName: 'Kopitiam Ali',
    phone: '+60 12-345 6789',
    website: 'https://kopitiam.example.com',
    address: '12 Jalan Makan',
    category: 'Malay',
    restaurantConfirmed: true,
    baseLocation: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
    adjustedLocation: const TouristLocation(
      latitude: 3.1391,
      longitude: 101.6870,
    ),
    landmarkPhoto: const LandmarkDraftPhoto(
      id: 'photo/landmark.jpg',
      url: 'https://cdn.example.com/landmark.jpg',
      type: 'signboard',
      captureLocation: TouristLocation(latitude: 3.1388, longitude: 101.6867),
    ),
    foods: <LandmarkDraftFood>[
      LandmarkDraftFood(
        food: _food(),
        price: 6.5,
        priceMin: 5,
        priceMax: 8,
        confidence: 0.91,
        dietaryRestrictions: const <String>['No Pork'],
        captureLocation: const TouristLocation(
          latitude: 3.1390,
          longitude: 101.6869,
        ),
        photo: const LandmarkDraftPhoto(
          id: 'photo/food-a.jpg',
          url: 'https://cdn.example.com/food-a.jpg',
        ),
      ),
      const LandmarkDraftFood(
        food: LocalFood(
          id: 12,
          name: 'Teh Tarik',
          description: '',
          origin: '',
          culturalBackground: '',
          ingredients: '',
          category: 'Beverage',
          cookingStyle: '',
          mealType: '',
          foodType: 'Beverage',
        ),
      ),
    ],
    operatingHours: <Weekday, List<OpeningHour>>{
      Weekday.monday: <OpeningHour>[
        const OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 9 * 60,
          closesAt: 17 * 60,
        ),
      ],
      Weekday.tuesday: <OpeningHour>[
        const OpeningHour(
          id: 0,
          day: Weekday.tuesday,
          status: DayStatus.unknown,
        ),
      ],
    },
    expiresAt: expiresAt ?? now.add(const Duration(hours: 24)),
    updatedAt: now,
  );
}

/// The draft's form snapshot as the data model would persist it, then read
/// back - exercising exactly the JSON the repository writes and reads.
LandmarkDraftDataModel _writeAndRead(LandmarkDraft draft) =>
    LandmarkDraftDataModel.fromJson(_draftModel(draft).toJson());

LandmarkDraftDataModel _draftModel(LandmarkDraft draft) {
  return LandmarkDraftDataModel(
    draftId: draft.id,
    touristId: 'tourist-1',
    restaurantName: draft.restaurantName,
    thumbnailUrl: draft.primaryFood?.photo?.url,
    phone: draft.phone,
    website: draft.website,
    address: draft.address,
    category: draft.category,
    restaurantConfirmed: draft.restaurantConfirmed,
    baseLatitude: draft.baseLocation.latitude,
    baseLongitude: draft.baseLocation.longitude,
    adjustedLatitude: draft.adjustedLocation.latitude,
    adjustedLongitude: draft.adjustedLocation.longitude,
    landmarkPhoto: LandmarkDraftPhotoDataModel(
      id: draft.landmarkPhoto!.id,
      url: draft.landmarkPhoto!.url,
      type: draft.landmarkPhoto!.type,
      captureLatitude: draft.landmarkPhoto!.captureLocation.isKnown
          ? draft.landmarkPhoto!.captureLocation.latitude
          : null,
      captureLongitude: draft.landmarkPhoto!.captureLocation.isKnown
          ? draft.landmarkPhoto!.captureLocation.longitude
          : null,
    ),
    foods: <LandmarkDraftFoodDataModel>[
      for (final LandmarkDraftFood food in draft.foods)
        LandmarkDraftFoodDataModel(
          food: LandmarkDraftDishDataModel(
            id: food.food.id,
            name: food.food.name,
            description: food.food.description,
            origin: food.food.origin,
            culturalBackground: food.food.culturalBackground,
            ingredients: food.food.ingredients,
            category: food.food.category,
            cookingStyle: food.food.cookingStyle,
            mealType: food.food.mealType,
            foodType: food.food.foodType,
            tastes: food.food.tastes,
            mainTaste: food.food.mainTaste,
            synonyms: food.food.synonyms,
          ),
          price: food.price,
          priceMin: food.priceMin,
          priceMax: food.priceMax,
          confidence: food.confidence,
          dietaryRestrictions: food.dietaryRestrictions,
          captureLatitude: food.captureLocation.isKnown
              ? food.captureLocation.latitude
              : null,
          captureLongitude: food.captureLocation.isKnown
              ? food.captureLocation.longitude
              : null,
          photo: food.photo == null
              ? null
              : LandmarkDraftPhotoDataModel(
                  id: food.photo!.id,
                  url: food.photo!.url,
                ),
        ),
    ],
    operatingHours: <LandmarkDraftHourDataModel>[
      for (final MapEntry<Weekday, List<OpeningHour>> entry
          in draft.operatingHours.entries)
        for (final OpeningHour hour in entry.value)
          LandmarkDraftHourDataModel(
            day: hour.day.name,
            status: hour.status.name,
            opensAt: hour.opensAt,
            closesAt: hour.closesAt,
          ),
    ],
    expiresAt: draft.expiresAt,
    updatedAt: draft.updatedAt,
  );
}

void main() {
  group('LandmarkSubmissionLogic.matchingDraft (continue, not duplicate)', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

    LandmarkDraft draftWith({
      required LocalFood food,
      required TouristLocation spot,
      String variant = '',
      int id = 7,
    }) => LandmarkDraft(
      id: id,
      restaurantName: 'Kopitiam Ali',
      baseLocation: spot,
      foods: <LandmarkDraftFood>[
        LandmarkDraftFood(food: food, variant: variant),
      ],
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      updatedAt: DateTime.now(),
    );

    const LocalFood nasiLemak = LocalFood(
      id: 10,
      name: 'Nasi Lemak',
      description: '',
      origin: '',
      culturalBackground: '',
      ingredients: '',
      category: 'Malay',
      cookingStyle: '',
      mealType: '',
      foodType: 'Food',
    );

    test('matches the same dish within 50 m of the saved spot', () {
      final LandmarkDraft saved = draftWith(
        food: nasiLemak,
        spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
      );

      final LandmarkDraft? match = logic.matchingDraft(
        drafts: <LandmarkDraft>[saved],
        food: nasiLemak,
        captureLocation: const TouristLocation(
          latitude: 3.1392,
          longitude: 101.6869,
        ), // ~22 m
      );

      expect(match?.id, 7);
    });

    test(
      'a differing variant - even a plain one - is NOT the same submission',
      () {
        // The draft recorded a variant this capture did not (the photo shows a
        // plain "Cendol", the draft holds "Cendol Jagung"): continuing it
        // would file the plain dish as that variant, so no draft is offered.
        final LandmarkDraft saved = draftWith(
          food: nasiLemak,
          variant: 'Nasi Lemak Ayam',
          spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
        );
        expect(
          logic.matchingDraft(
            drafts: <LandmarkDraft>[saved],
            food: nasiLemak,
            captureLocation: const TouristLocation(
              latitude: 3.1390,
              longitude: 101.6869,
            ),
          ),
          isNull,
        );

        // ...and the reverse: the draft is plain, this capture is a variant.
        final LandmarkDraft plain = draftWith(
          food: nasiLemak,
          spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
        );
        expect(
          logic.matchingDraft(
            drafts: <LandmarkDraft>[plain],
            food: nasiLemak,
            variant: 'Nasi Lemak Ayam',
            captureLocation: const TouristLocation(
              latitude: 3.1390,
              longitude: 101.6869,
            ),
          ),
          isNull,
        );
      },
    );

    test('two DIFFERENT non-empty variants are a different dish', () {
      final LandmarkDraft saved = draftWith(
        food: nasiLemak,
        variant: 'Nasi Lemak Ayam',
        spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
      );

      expect(
        logic.matchingDraft(
          drafts: <LandmarkDraft>[saved],
          food: nasiLemak,
          variant: 'Nasi Lemak Special',
          captureLocation: const TouristLocation(
            latitude: 3.1390,
            longitude: 101.6869,
          ),
        ),
        isNull,
      );

      // The same variant matches - compared case/punctuation-insensitively.
      expect(
        logic
            .matchingDraft(
              drafts: <LandmarkDraft>[saved],
              food: nasiLemak,
              variant: '  nasi   LEMAK ayam ',
              captureLocation: const TouristLocation(
                latitude: 3.1390,
                longitude: 101.6869,
              ),
            )
            ?.id,
        7,
      );
    });

    test('matches by script-folded name and by catalogue id', () {
      final LandmarkDraft byName = draftWith(
        food: const LocalFood(
          id: 0,
          name: '福建麵',
          description: '',
          origin: '',
          culturalBackground: '',
          ingredients: '',
          category: 'Chinese',
          cookingStyle: '',
          mealType: '',
          foodType: 'Food',
        ),
        spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
      );
      expect(
        logic
            .matchingDraft(
              drafts: <LandmarkDraft>[byName],
              food: const LocalFood(
                id: 0,
                name: '福建面', // simplified sibling
                description: '',
                origin: '',
                culturalBackground: '',
                ingredients: '',
                category: 'Chinese',
                cookingStyle: '',
                mealType: '',
                foodType: 'Food',
              ),
              captureLocation: const TouristLocation(
                latitude: 3.1390,
                longitude: 101.6869,
              ),
            )
            ?.id,
        7,
      );

      final LandmarkDraft byId = draftWith(
        food: nasiLemak,
        spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
      );
      expect(
        logic
            .matchingDraft(
              drafts: <LandmarkDraft>[byId],
              // Same catalogue row, renamed upstream (A13.1 merge).
              food: const LocalFood(
                id: 10,
                name: 'Nasi Lemak Special',
                description: '',
                origin: '',
                culturalBackground: '',
                ingredients: '',
                category: 'Malay',
                cookingStyle: '',
                mealType: '',
                foodType: 'Food',
              ),
              captureLocation: const TouristLocation(
                latitude: 3.1390,
                longitude: 101.6869,
              ),
            )
            ?.id,
        7,
      );
    });

    test('a different dish, or a spot >50 m away, never matches', () {
      final LandmarkDraft saved = draftWith(
        food: nasiLemak,
        spot: const TouristLocation(latitude: 3.1390, longitude: 101.6869),
      );

      // Same spot, different dish.
      expect(
        logic.matchingDraft(
          drafts: <LandmarkDraft>[saved],
          food: const LocalFood(
            id: 99,
            name: 'Roti Canai',
            description: '',
            origin: '',
            culturalBackground: '',
            ingredients: '',
            category: 'Malay',
            cookingStyle: '',
            mealType: '',
            foodType: 'Food',
          ),
          captureLocation: const TouristLocation(
            latitude: 3.1390,
            longitude: 101.6869,
          ),
        ),
        isNull,
      );

      // Same dish ~2 km away - a different restaurant, never resumed.
      expect(
        logic.matchingDraft(
          drafts: <LandmarkDraft>[saved],
          food: nasiLemak,
          captureLocation: const TouristLocation(
            latitude: 3.1600,
            longitude: 101.7000,
          ),
        ),
        isNull,
      );
    });

    test('an unknown fix on either side can never match', () {
      expect(
        logic.matchingDraft(
          drafts: <LandmarkDraft>[
            draftWith(food: nasiLemak, spot: TouristLocation.unknown),
          ],
          food: nasiLemak,
          captureLocation: const TouristLocation(
            latitude: 3.1390,
            longitude: 101.6869,
          ),
        ),
        isNull,
      );
      expect(
        logic.matchingDraft(
          drafts: <LandmarkDraft>[
            draftWith(
              food: nasiLemak,
              spot: const TouristLocation(
                latitude: 3.1390,
                longitude: 101.6869,
              ),
            ),
          ],
          food: nasiLemak,
          captureLocation: TouristLocation.unknown,
        ),
        isNull,
      );
    });
  });

  group(
    'LandmarkSubmissionLogic.matchingDraftForRestaurant (Confirm merge)',
    () {
      final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

      const TouristLocation spot = TouristLocation(
        latitude: 3.1390,
        longitude: 101.6869,
      );

      LandmarkDraft restaurantDraft(String name, TouristLocation at) =>
          LandmarkDraft(
            id: 7,
            restaurantName: name,
            baseLocation: at,
            foods: const <LandmarkDraftFood>[],
            expiresAt: DateTime.now().add(const Duration(hours: 24)),
            updatedAt: DateTime.now(),
          );

      test('the same restaurant name within 100 m matches', () {
        expect(
          logic
              .matchingDraftForRestaurant(
                drafts: <LandmarkDraft>[restaurantDraft('KOPITIAM ALI', spot)],
                // Case-folding only - the SAME name.
                restaurantName: 'Kopitiam Ali',
                // ~55 m north - still the same restaurant (100 m rule).
                formLocation: const TouristLocation(
                  latitude: 3.1395,
                  longitude: 101.6869,
                ),
              )
              ?.id,
          7,
        );
      });

      test('a different name, or a spot beyond 100 m, never matches', () {
        // Same name, ~220 m away - a different branch.
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[restaurantDraft('Kopitiam Ali', spot)],
            restaurantName: 'Kopitiam Ali',
            formLocation: const TouristLocation(
              latitude: 3.1410,
              longitude: 101.6869,
            ),
          ),
          isNull,
        );
        // Same spot, a different restaurant.
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[restaurantDraft('Kopitiam Ali', spot)],
            restaurantName: 'Restoran Lain',
            formLocation: spot,
          ),
          isNull,
        );
      });

      test('a blank name or an unknown fix can never match', () {
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[restaurantDraft('Kopitiam Ali', spot)],
            restaurantName: '   ',
            formLocation: spot,
          ),
          isNull,
        );
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[restaurantDraft('', spot)],
            restaurantName: 'Kopitiam Ali',
            formLocation: spot,
          ),
          isNull,
        );
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[
              restaurantDraft('Kopitiam Ali', TouristLocation.unknown),
            ],
            restaurantName: 'Kopitiam Ali',
            formLocation: spot,
          ),
          isNull,
        );
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[restaurantDraft('Kopitiam Ali', spot)],
            restaurantName: 'Kopitiam Ali',
            formLocation: TouristLocation.unknown,
          ),
          isNull,
        );
      });

      test('a form continuing its own draft never re-matches itself', () {
        expect(
          logic.matchingDraftForRestaurant(
            drafts: <LandmarkDraft>[restaurantDraft('Kopitiam Ali', spot)],
            restaurantName: 'Kopitiam Ali',
            formLocation: spot,
            // This form IS row 7 (opened from the incomplete list).
            excludeDraftId: 7,
          ),
          isNull,
        );
      });

      test(
        'an excluded row still lets ANOTHER draft of the restaurant match',
        () {
          expect(
            logic
                .matchingDraftForRestaurant(
                  drafts: <LandmarkDraft>[
                    restaurantDraft('Kopitiam Ali', spot), // id 7 - this form.
                    LandmarkDraft(
                      id: 9,
                      restaurantName: 'Kopitiam Ali',
                      baseLocation: spot,
                      foods: const <LandmarkDraftFood>[],
                      expiresAt: DateTime.now().add(const Duration(hours: 24)),
                      updatedAt: DateTime.now(),
                    ),
                  ],
                  restaurantName: 'Kopitiam Ali',
                  formLocation: spot,
                  excludeDraftId: 7,
                )
                ?.id,
            9,
          );
        },
      );
    },
  );

  group('LandmarkDraft expiry', () {
    test('a fresh draft is not expired and reports its remaining time', () {
      final LandmarkDraft draft = _draft();
      expect(draft.isExpired, isFalse);
      expect(draft.timeUntilExpiry.inHours, greaterThanOrEqualTo(23));
    });

    test('a draft past its 24-hour expiry reports empty remaining time', () {
      final LandmarkDraft draft = _draft(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(draft.isExpired, isTrue);
      expect(draft.timeUntilExpiry, Duration.zero);
    });
  });

  group('LandmarkDraft hasContent / thumbnail', () {
    test('a draft with only a name still counts as content', () {
      final LandmarkDraft draft = LandmarkDraft(
        id: 0,
        restaurantName: 'Kopitiam Ali',
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        updatedAt: DateTime.now(),
      );
      expect(draft.hasContent, isTrue);
    });

    test('an empty draft has no content', () {
      final LandmarkDraft draft = LandmarkDraft(
        id: 0,
        restaurantName: '  ',
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        updatedAt: DateTime.now(),
      );
      expect(draft.hasContent, isFalse);
    });

    test('the thumbnail prefers the primary food photo', () {
      final LandmarkDraft draft = _draft();
      expect(draft.thumbnailPhoto?.url, 'https://cdn.example.com/food-a.jpg');
    });
  });

  group('LandmarkDraftDataModel JSON round trip', () {
    test(
      'a payload from before the confirmation existed reads as unconfirmed',
      () {
        // Only the NEW key is missing - an older saved submission.
        final Map<String, dynamic> old = _draftModel(_draft()).toJson();
        (old['payload'] as Map<String, dynamic>).remove('restaurant_confirmed');
        expect(
          LandmarkDraftDataModel.fromJson(old).restaurantConfirmed,
          isFalse,
        );
      },
    );

    test('every form field survives writing and reading the payload', () {
      final LandmarkDraft draft = _draft();
      final LandmarkDraftDataModel read = _writeAndRead(draft);

      expect(read.draftId, 7);
      expect(read.touristId, 'tourist-1');
      expect(read.restaurantName, 'Kopitiam Ali');
      expect(read.phone, '+60 12-345 6789');
      expect(read.website, 'https://kopitiam.example.com');
      expect(read.address, '12 Jalan Makan');
      expect(read.category, 'Malay');
      expect(read.baseLatitude, closeTo(3.1390, 0.00001));
      expect(read.baseLongitude, closeTo(101.6869, 0.00001));
      expect(read.adjustedLatitude, closeTo(3.1391, 0.00001));
      expect(read.landmarkPhoto?.id, 'photo/landmark.jpg');
      expect(read.landmarkPhoto?.type, 'signboard');
      expect(read.thumbnailUrl, 'https://cdn.example.com/food-a.jpg');

      // The restaurant confirmation and the signboard photo's OWN fix are
      // part of the payload: a resumed form knows both without the tourist
      // re-confirming or re-capturing.
      expect(read.restaurantConfirmed, isTrue);
      expect(read.landmarkPhoto?.captureLatitude, closeTo(3.1388, 0.00001));
      expect(read.landmarkPhoto?.captureLongitude, closeTo(101.6867, 0.00001));

      expect(read.foods.length, 2);
      final LandmarkDraftFoodDataModel primary = read.foods.first;
      expect(primary.food.name, 'Nasi Lemak');
      expect(primary.food.tastes, <String>['Spicy']);
      expect(primary.food.mainTaste, 'Spicy');
      expect(primary.food.synonyms, <String>['Nasi Lemak Ayam']);
      expect(primary.price, 6.5);
      expect(primary.priceMin, 5);
      expect(primary.priceMax, 8);
      expect(primary.confidence, closeTo(0.91, 0.0001));
      expect(primary.dietaryRestrictions, <String>['No Pork']);
      expect(primary.captureLatitude, closeTo(3.1390, 0.00001));
      expect(primary.photo?.url, 'https://cdn.example.com/food-a.jpg');

      final LandmarkDraftFoodDataModel second = read.foods[1];
      expect(second.food.name, 'Teh Tarik');
      expect(second.price, isNull);
      expect(second.photo, isNull);

      final List<LandmarkDraftHourDataModel> mondayRows = read.operatingHours
          .where((LandmarkDraftHourDataModel hour) => hour.day == 'monday')
          .toList();
      expect(mondayRows.length, 1);
      expect(mondayRows.first.status, 'open');
      expect(mondayRows.first.opensAt, 9 * 60);
      expect(mondayRows.first.closesAt, 17 * 60);

      expect(
        read.operatingHours
            .where((LandmarkDraftHourDataModel hour) => hour.day == 'tuesday')
            .first
            .status,
        'unknown',
      );
    });

    test('a row without a payload parses to an empty but safe draft', () {
      final LandmarkDraftDataModel read =
          LandmarkDraftDataModel.fromJson(<String, dynamic>{
            'draft_id': 3,
            'tourist_id': 'tourist-1',
            'expires_at': '2026-09-11T10:00:00.000Z',
          });
      expect(read.draftId, 3);
      expect(read.foods, isEmpty);
      expect(read.operatingHours, isEmpty);
      expect(read.restaurantName, '');
      expect(read.landmarkPhoto, isNull);
    });
  });
}
