/// What a tourist's report submission produced. One submission may carry
/// several [ReportClaim]s (e.g. an operating-hours report that corrects
/// several days), so the outcome aggregates across all of them.
///
/// Domain models are plain data types. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class ReportSubmitOutcome {
  const ReportSubmitOutcome({
    this.requiresSignIn = false,
    this.alreadyReported = false,
    this.submittedCount = 0,
    this.duplicateCount = 0,
    this.placeHiddenNow = false,
    this.applied = const <String>[],
  });

  /// True when no tourist was signed in - nothing was written.
  final bool requiresSignIn;

  /// True when EVERY claim in the submission was a duplicate (this tourist
  /// had already reported each specific issue) - nothing new was written.
  final bool alreadyReported;

  /// How many NEW claim rows were inserted.
  final int submittedCount;

  /// How many claims were skipped as duplicates.
  final int duplicateCount;

  /// True when one of the claims crossed a threshold THIS submission and the
  /// auto-apply hid the place (froze it or removed it) - the UI leaves the
  /// page and refreshes the map, exactly like the old freeze UX.
  final bool placeHiddenNow;

  /// Human-readable labels of the fixes that were auto-applied (for the
  /// confirmation message), e.g. ['Monday hours', 'Nasi Lemak price'].
  final List<String> applied;
}
