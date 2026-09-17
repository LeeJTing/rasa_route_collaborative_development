import '../../domain_model/landmark_draft.dart';
import '../repositories/landmark_repository_facade.dart';
import 'landmark_submission_logic.dart';

/// Saving, listing and discarding incomplete Add-New-Landmark forms.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
///
/// A draft lives for [_draftLifetime] (24 hours) from its LAST save - the
/// expiry is stamped here, not by the ViewModel or the repository, because
/// it is a product rule about how long an unfinished submission stays worth
/// resuming. Drafts past their expiry are deleted the next time they are
/// read (row + their uploaded photos), so a tourist never resumes a stale
/// form and the photos do not linger.
class LandmarkDraftLogic {
  LandmarkDraftLogic();

  final LandmarkRepositoryFacade repository = LandmarkRepositoryFacade();

  /// How long a draft stays resumable after its last save.
  static const Duration draftLifetime = Duration(hours: 24);

  /// Saves [draft] for the signed-in tourist and returns its draft id.
  /// Returns 0 without writing when nobody is signed in (drafts are only
  /// kept for a known tourist). `updatedAt`/`expiresAt` are stamped here.
  Future<int> saveDraft(LandmarkDraft draft) async {
    final String touristId = await _currentTouristId();
    if (touristId.isEmpty) return 0;
    final DateTime now = DateTime.now();
    return repository.saveDraft(
      touristId: touristId,
      draft: LandmarkDraft(
        id: draft.id,
        restaurantName: draft.restaurantName,
        phone: draft.phone,
        website: LandmarkSubmissionLogic.sanitiseWebsiteForSave(draft.website),
        address: draft.address,
        category: draft.category,
        restaurantConfirmed: draft.restaurantConfirmed,
        baseLocation: draft.baseLocation,
        adjustedLocation: draft.adjustedLocation,
        landmarkPhoto: draft.landmarkPhoto,
        foods: draft.foods,
        operatingHours: draft.operatingHours,
        expiresAt: now.add(draftLifetime),
        updatedAt: now,
      ),
    );
  }

  /// The signed-in tourist's resumable drafts, newest first. Expired drafts
  /// are deleted on the way (row + photos) so they can never be resumed or
  /// listed again. Failures on one draft never hide the others.
  Future<List<LandmarkDraft>> pendingDrafts() async {
    final String touristId = await _currentTouristId();
    if (touristId.isEmpty) return const <LandmarkDraft>[];
    final List<LandmarkDraft> drafts = await repository.draftsByTourist(
      touristId,
    );
    final List<LandmarkDraft> resumable = <LandmarkDraft>[];
    for (final LandmarkDraft draft in drafts) {
      if (!draft.isExpired) {
        resumable.add(draft);
        continue;
      }
      try {
        await repository.deleteDraft(draft);
      } catch (_) {
        // Purge is best-effort - a draft that fails to delete simply gets
        // another chance next time; it is not returned as resumable.
      }
    }
    return resumable;
  }

  /// Discards one draft (the tourist chose not to continue it) - the row and
  /// its uploaded photos are deleted.
  Future<void> deleteDraft(LandmarkDraft draft) =>
      repository.deleteDraft(draft);

  /// Removes a draft ROW after a successful submission - its photos are NOT
  /// deleted, because the submitted landmark now stores those same objects.
  Future<void> clearSubmittedDraft(int draftId) =>
      repository.deleteDraftRow(draftId);

  /// Deletes one uploaded photo by its storage object name - used when a
  /// draft's photo is replaced by a fresh capture, so the old object does
  /// not linger (best-effort).
  Future<void> deletePhoto(String objectId) =>
      repository.deleteDraftPhoto(objectId);

  Future<String> _currentTouristId() async {
    final String? touristId = await repository.currentTouristId();
    return touristId ?? '';
  }
}
