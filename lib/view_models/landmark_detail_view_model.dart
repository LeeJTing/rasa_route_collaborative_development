import 'package:image_picker/image_picker.dart';

import '../app/routing/app_navigator.dart';
import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'food_recognition_view_model.dart'
    show AdditionalFoodCaptureResult, LandmarkDraftHandoff;

/// ViewModel for `LandmarkDetailView`.
///
/// Read-only, full-detail look at a recognized food - reached from
/// `FoodRecognitionView`'s result popup ("View Details", A6) or from
/// `AddLandmarkView`'s "Recognised Food" card chevron.
///
/// Owns only what this screen needs: the food, its photo, and the "Add New
/// Landmark" action. Previously this screen borrowed
/// `FoodRecognitionViewModel` instead of having its own ViewModel - that
/// meant depending on a class also carrying camera-capture state
/// (isProcessing, recognitionError, multipleResults, purpose,
/// signboard/stall fields) this screen never touches. A dedicated
/// ViewModel avoids that.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class LandmarkDetailViewModel extends BaseViewModel {
  LandmarkDetailViewModel();

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  LocalFood? _recognizedFood;
  XFile? _capturedImage;

  /// Whether the confirm button should return this food to the *existing*
  /// `AddLandmarkView` (additional-food flow) instead of pushing a fresh
  /// form (primary flow). Set from `LandmarkDraftHandoff` in the View's
  /// `initState` - see
  /// `LandmarkDraftHandoff.pendingReturnToFormAsAdditionalFood`.
  bool _returnToFormAsAdditionalFood = false;

  LocalFood? get recognizedFood => _recognizedFood;
  XFile? get capturedImage => _capturedImage;
  bool get returnToFormAsAdditionalFood => _returnToFormAsAdditionalFood;

  void setReturnToFormAsAdditionalFood(bool value) {
    _returnToFormAsAdditionalFood = value;
  }

  /// Set from `LandmarkDraftHandoff` in the View's `initState`, before
  /// `onInit()` - see that class's doc.
  void setRecognizedFood(LocalFood food) {
    _recognizedFood = food;
    safeNotifyListeners();
  }

  /// Set alongside [setRecognizedFood] - see
  /// `LandmarkDraftHandoff.pendingCapturedImage`.
  void setCapturedImage(XFile image) {
    _capturedImage = image;
    safeNotifyListeners();
  }

  /// "Add New Landmark" (primary flow) or "Add to Landmark" (additional-food
  /// flow) - hands the recognized food (and its photo) onward. The primary
  /// flow pushes a fresh `AddLandmarkView`; the additional-food flow pops the
  /// detail screen and the camera screen back to the *existing* form, handing
  /// the food back through [AdditionalFoodCaptureResult] (see
  /// [_returnToFormAsAdditionalFood]).
  void proceedToAddLandmark() {
    final LocalFood? food = _recognizedFood;
    if (food == null) return;
    if (_returnToFormAsAdditionalFood) {
      final XFile? image = _capturedImage;
      if (image == null) return;
      // Pop LandmarkDetailView, then pop the FoodRecognitionView below it
      // WITH the result - which completes `AddLandmarkViewModel.openAddMoreFood`'s
      // await, so the food lands in the existing form's additional-foods list.
      AppNavigator.pop();
      AppNavigator.pop<AdditionalFoodCaptureResult>((food: food, image: image));
      return;
    }
    LandmarkDraftHandoff().pushAddLandmark(food, _capturedImage);
  }
}
