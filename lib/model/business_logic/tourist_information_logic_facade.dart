import 'authenticate_logic.dart';
import 'user_profile_logic.dart';

/// Auth and profile. Used by the LoginRegister, Otp, ProfileSetUp and Profile ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class TouristInformationLogicFacade {
  TouristInformationLogicFacade();

  final AuthenticateLogic authenticate = AuthenticateLogic();
  final UserProfileLogic userProfile = UserProfileLogic();
}
