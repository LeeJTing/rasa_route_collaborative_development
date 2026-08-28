/// Every route name in the app, in one place.
///
/// These are plain `String` constants. The route table itself lives in
/// `MaterialApp(routes: ...)` in `lib/app/app.dart`.
///
/// RULE: never type a route string literal at a call site. Always
/// `Navigator.pushNamed(context, AppRoutes.foodDetail)`. A typo in a literal
/// is a runtime crash; a typo here is a compile error.
abstract final class AppRoutes {
  const AppRoutes._();

  // --- Entry / auth ---------------------------------------------------------

  /// Initial route. Hosts `LoginRegisterView`.
  static const String loginRegister = '/';

  /// One-time-password verification.
  static const String otp = '/otp';

  /// First-run profile capture.
  static const String profileSetUp = '/profile-set-up';

  // --- Shell ----------------------------------------------------------------

  /// Bottom-navigation shell: dashboard / recognition / local food.
  static const String mainShell = '/main';

  // --- Tabs (also reachable standalone) -------------------------------------

  static const String dashboard = '/dashboard';
  static const String foodRecognition = '/food-recognition';
  static const String localFoodList = '/local-food-list';

  // --- Tourist ---------------------------------------------------------------

  static const String profile = '/profile';
  static const String favouriteCollection = '/favourite-collection';

  // --- Food ------------------------------------------------------------------

  static const String foodDetail = '/food-detail';
  static const String foodComparison = '/food-comparison';
  static const String foodRecommendation = '/food-recommendation';

  // --- Restaurant ------------------------------------------------------------

  static const String restaurantRecommendation = '/restaurant-recommendation';
  static const String restaurantDetail = '/restaurant-detail';
  static const String restaurantItemList = '/restaurant-item-list';

  // --- Landmark --------------------------------------------------------------

  static const String landmarkHistory = '/landmark-history';
  static const String addLandmark = '/add-landmark';
  static const String restaurantSignboard = '/restaurant-signboard';
  static const String landmarkDetail = '/landmark-detail';

  /// Full details of a tourist-submitted landmark, opened from the map's
  /// "View Landmark" button. Distinct from [landmarkDetail], which is the
  /// recognized-food detail screen in the capture flow.
  static const String landmarkPlaceDetail = '/landmark-place-detail';

  /// One dish attached to a tourist-submitted landmark, opened by tapping a
  /// dish card on [landmarkPlaceDetail]. Distinct from [foodDetail] (the
  /// catalogue's `LocalFood` detail screen, fetched by id) - this reads
  /// straight off the `LandmarkItem` already in hand via
  /// `LandmarkItemHandoff`, no network fetch.
  static const String landmarkItemDetail = '/landmark-item-detail';

  /// Every registered name - used by tests to assert the route table is
  /// complete.
  static const List<String> all = <String>[
    loginRegister,
    otp,
    profileSetUp,
    mainShell,
    dashboard,
    foodRecognition,
    localFoodList,
    profile,
    favouriteCollection,
    foodDetail,
    foodComparison,
    foodRecommendation,
    restaurantRecommendation,
    restaurantDetail,
    restaurantItemList,
    landmarkHistory,
    addLandmark,
    restaurantSignboard,
    landmarkDetail,
    landmarkPlaceDetail,
    landmarkItemDetail,
  ];
}
