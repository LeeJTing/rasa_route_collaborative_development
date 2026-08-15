import '../facades/tourist_repository_facade.dart';
import '../../../external/supabase/supabase_service.dart';

class FoodKnowledgeRepository implements TouristRepository {
  final SupabaseService supabaseService;

  FoodKnowledgeRepository({required this.supabaseService});

  // TODO: Implement TouristRepository using external data source clients only.
}
