import '../../domain_model/app_tutorial.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';
import '../data_models/tutorial_progress_data_model.dart';

/// Whether this device has been shown the guided walkthrough (REQ107).
///
/// A repository is the only layer that talks to the shared clients. This one
/// talks to exactly one of them - [LocalStorageManager] - because the answer
/// never leaves the phone: it is a property of the installation, not of the
/// account, and a tourist who reinstalls is a first-time user again.
///
/// It reuses the storage key the project already declared for this
/// (`LocalStorageManager.keyHasSeenOnboarding`), which had never been written.
/// The value under it is the JSON record rather than a bare flag, because
/// "has it been seen" was never enough to answer "should it be shown again".
class TutorialRepository {
  TutorialRepository();

  final LocalStorageManager storage = LocalStorageManager();

  /// What the device remembers, or [TutorialProgress.never] when it remembers
  /// nothing - which is also what a corrupt or half-written record reads as.
  /// Failing closed here would hide the tutorial from the very tourist it
  /// exists for; failing open costs one extra walkthrough.
  TutorialProgress read() {
    final Map<String, dynamic>? json = storage.readJson(_key);
    if (json == null) return TutorialProgress.never;
    final TutorialProgressDataModel data = TutorialProgressDataModel.fromJson(
      json,
    );
    if (data.shownAt == null) return TutorialProgress.never;
    return TutorialProgress(
      completed: data.completed,
      shownAt: data.shownAt,
      version: data.version,
    );
  }

  /// Records that the tutorial was dismissed, and when.
  Future<void> write(TutorialProgress progress) {
    final TutorialProgressDataModel data = TutorialProgressDataModel(
      completed: progress.completed,
      shownAt: progress.shownAt,
      version: progress.version,
    );
    return storage.writeJson(_key, data.toJson());
  }

  /// Forgets everything, so the next launch is a first launch. Nothing in the
  /// app calls this; it is here for a debug build and for a test to reset
  /// between cases.
  Future<void> clear() => storage.remove(_key);

  static const String _key = LocalStorageManager.keyHasSeenOnboarding;
}
