import '../core/base_view_model.dart';
import '../domain_model/submitted_landmark.dart';

/// ViewModel for `LandmarkItemDetailView` - one dish attached to a
/// tourist-submitted landmark, reached by tapping a dish card on
/// `LandmarkPlaceDetailView`.
///
/// Deliberately holds no logic facade and does no async loading: the tapped
/// `LandmarkItem`'s full data already came from `LandmarkPlaceDetailView`'s
/// own load of the landmark - there is nothing left to fetch. This is
/// purely a display screen.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * state goes in private fields with read-only getters.
class LandmarkItemDetailViewModel extends BaseViewModel {
  LandmarkItemDetailViewModel();

  LandmarkItem? _item;
  LandmarkItem? get item => _item;

  /// Set from `LandmarkItemHandoff` in the View's `initState`, before
  /// `onInit()` - see that class's doc.
  void setItem(LandmarkItem item) {
    _item = item;
  }

  @override
  Future<void> onInit() async {
    if (_item == null) setError('No dish selected.');
  }
}
