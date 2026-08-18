import 'package:flutter/material.dart';

import '../views/add_landmark_view/add_landmark_view.dart';
import '../views/dashboard_view/dashboard_view.dart';
import '../views/favourite_collection_view/favourite_collection_view.dart';
import '../views/food_comparison_view/food_comparison_view.dart';
import '../views/food_detail_view/food_detail_view.dart';
import '../views/food_recognition_view/food_recognition_view.dart';
import '../views/food_recommendation_view/food_recommendation_view.dart';
import '../views/landmark_detail_view/landmark_detail_view.dart';
import '../views/landmark_history_view/landmark_history_view.dart';
import '../views/local_food_list_view/local_food_list_view.dart';
import '../views/login_register_view/login_register_view.dart';
import '../views/main_shell_view/main_shell_view.dart';
import '../views/opt_view/otp_view.dart';
import '../views/profile_set_up_view/profile_set_up_view.dart';
import '../views/profile_view/profile_view.dart';
import '../views/restaurant_detail_view/restaurant_detail_view.dart';
import '../views/restaurant_item_list_view/restaurant_item_list_view.dart';
import '../views/restaurant_recommendation_view/restaurant_recommendation_view.dart';
import 'routing/app_navigator.dart';
import 'routing/app_routes.dart';
import 'theme/app_theme.dart';

/// The root widget.
///
/// It does three things and nothing else:
///   1. installs the one [ThemeData];
///   2. holds the route table, right here in `MaterialApp(routes: ...)`;
///   3. hands its navigator key to `AppNavigator` so ViewModels can navigate
///      without a `BuildContext`.
///
/// Note what is NOT here: there is no `MultiProvider` and no dependency
/// container. Each View constructs its own ViewModel with `XViewModel()` and
/// declares its own `ChangeNotifierProvider`. Every layer below does the same -
/// a class creates whatever it needs itself. See any file in `lib/views/`.
class RasaRouteApp extends StatelessWidget {
  const RasaRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rasa Route',
      debugShowCheckedModeBanner: false,

      // Theme: lib/app/theme/. Never style a screen inline.
      theme: AppTheme.light,

      navigatorKey: AppNavigator.navigatorKey,
      initialRoute: AppRoutes.loginRegister,

      // The route table. Names come from AppRoutes so no call site types a
      // string literal. Adding a screen is two edits: a constant there, an
      // entry here.
      routes: <String, WidgetBuilder>{
        AppRoutes.loginRegister: (BuildContext context) =>
            const LoginRegisterView(),
        AppRoutes.otp: (BuildContext context) => const OtpView(),
        AppRoutes.profileSetUp: (BuildContext context) =>
            const ProfileSetUpView(),

        AppRoutes.mainShell: (BuildContext context) => const MainShellView(),

        AppRoutes.dashboard: (BuildContext context) => const DashboardView(),
        AppRoutes.foodRecognition: (BuildContext context) =>
            const FoodRecognitionView(),
        AppRoutes.localFoodList: (BuildContext context) =>
            const LocalFoodListView(),

        AppRoutes.profile: (BuildContext context) => const ProfileView(),
        AppRoutes.favouriteCollection: (BuildContext context) =>
            const FavouriteCollectionView(),

        AppRoutes.foodDetail: (BuildContext context) => const FoodDetailView(),
        AppRoutes.foodComparison: (BuildContext context) =>
            const FoodComparisonView(),
        AppRoutes.foodRecommendation: (BuildContext context) =>
            const FoodRecommendationView(),

        AppRoutes.restaurantRecommendation: (BuildContext context) =>
            const RestaurantRecommendationView(),
        AppRoutes.restaurantDetail: (BuildContext context) =>
            const RestaurantDetailView(),
        AppRoutes.restaurantItemList: (BuildContext context) =>
            const RestaurantItemListView(),

        AppRoutes.landmarkHistory: (BuildContext context) =>
            const LandmarkHistoryView(),
        AppRoutes.addLandmark: (BuildContext context) =>
            const AddLandmarkView(),
        AppRoutes.landmarkDetail: (BuildContext context) =>
            const LandmarkDetailView(),
      },
    );
  }
}
