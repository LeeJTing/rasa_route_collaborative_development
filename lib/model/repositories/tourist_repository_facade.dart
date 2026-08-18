import 'auth_repository.dart';
import 'interaction_repository.dart';
import 'tourist_profile_repository.dart';

/// Everything about who the tourist is: session, profile and interactions.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class TouristRepositoryFacade {
  TouristRepositoryFacade();

  final AuthRepository auth = AuthRepository();
  final TouristProfileRepository profile = TouristProfileRepository();
  final InteractionRepository interaction = InteractionRepository();
}
