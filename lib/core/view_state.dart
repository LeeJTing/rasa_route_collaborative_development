/// The four states every screen in Rasa Route can be in.
///
/// Views switch on this instead of juggling their own `isLoading` /
/// `errorMessage` booleans, which keeps loading and error handling identical
/// across all 18 screens.
enum ViewState {
  /// Nothing has been requested yet.
  idle,

  /// A request is in flight - show a spinner or skeleton.
  busy,

  /// The request succeeded and data is ready to render.
  ready,

  /// The request failed - show the error state with a retry action.
  error;

  bool get isIdle => this == ViewState.idle;
  bool get isBusy => this == ViewState.busy;
  bool get isReady => this == ViewState.ready;
  bool get isError => this == ViewState.error;
}
