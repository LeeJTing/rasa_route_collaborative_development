import '../facades/food_repository_facade.dart';
import '../../../external/supabase/supabase_service.dart';
import '../../../external/gemini/gemini_service.dart';

class RecommendationRepository implements FoodRepository {
  final SupabaseService supabaseService;
  final GeminiService geminiService;

  RecommendationRepository({
    required this.supabaseService,
    required this.geminiService,
  });

  // TODO: Implement FoodRepository using external data source clients only.
}
