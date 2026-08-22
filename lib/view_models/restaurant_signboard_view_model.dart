import '../core/base_view_model.dart';

/// ViewModel for `RestaurantSignboardView`.
///
/// NOT USED by the current UC500 flow. Signboard/stall capture now happens
/// through `FoodRecognitionView`/`FoodRecognitionViewModel` (reused across
/// three capture purposes - see `FoodRecognitionPurpose`), reached via
/// `AddLandmarkViewModel.openSignboardCapture()`/`openStallCapture()`.
///
/// This file is left as a harmless, compiling placeholder rather than
/// deleted or repurposed - it isn't in scope to build out further here.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * state goes in private fields with read-only getters.
class RestaurantSignboardViewModel extends BaseViewModel {
  RestaurantSignboardViewModel();
}
