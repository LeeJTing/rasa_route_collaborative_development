import '../../external/gemini/gemini_service.dart';
import '../../external/supabase/supabase_service.dart';

/// The single remote data source for the whole app.
///
/// Repositories depend on `APIManager`, never on `SupabaseService` or
/// `GeminiService` directly. That keeps every network concern - table names,
/// select strings, storage buckets, error translation - in one file.
///
/// It returns raw rows. Turning a row into an object is the **data model's**
/// job (`LocalFoodDataModel.fromJson(row)`); turning that into something the
/// app reasons about is the **repository's** job (data model -> domain model).
///
/// A singleton: `APIManager()` always returns the same instance, so no one has
/// to pass it down through constructors.
class APIManager {
  factory APIManager() => _instance;

  APIManager._();

  static final APIManager _instance = APIManager._();

  final SupabaseService _supabase = SupabaseService();
  final GeminiService _gemini = GeminiService();

  SupabaseService get supabase => _supabase;

}
