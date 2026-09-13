import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
// `show` keeps this to the orientation API: `services.dart` also re-exports
// `dart:typed_data`, which this file already imports directly.
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:provider/provider.dart';

import '../../app/config/env.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/landmark_draft.dart';
import '../../view_models/food_recognition_view_model.dart';
import '../common_widgets/add_landmark_reminder_dialog.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/continue_draft_dialog.dart';
import '../common_widgets/mock_gps_button.dart';
import '../common_widgets/unfinished_submission_dialog.dart';
import 'widgets/multiple_results_card.dart';
import 'widgets/recognition_result_card.dart';

/// Camera capture + recognition screen (UC500, REQ106_1). Reused for four
/// purposes - see [FoodRecognitionPurpose] - which arrives through
/// `LandmarkDraftHandoff` and picks the on-screen instruction and what
/// happens after a successful capture. The title stays "Add New Landmark"
/// throughout, regardless of purpose - see [_titleFor].
///
/// Per REQ106_1, capture happens on an in-app camera view with a frame
/// overlay - not a hand-off to the platform's own camera app - so this owns
/// a `CameraController` directly and renders `CameraPreview`.
///
/// The screen is portrait-only (user request: the camera is always used
/// vertically), locked when the screen opens and released when it closes -
/// which also keeps the preview, the frame guide and the crop maths in
/// agreement, since those are written for a portrait display.
///
/// Per BF-8, the recognition result is shown as a popup OVER the captured
/// photo (dimmed), not a full navigation and not the live camera feed still
/// running underneath. The photo stays frozen there until the tourist closes
/// the popup (the shared X button), which is the one way back to the live
/// camera - see [_CameraViewfinder]'s `frozenImage`. The screen only
/// actually navigates away when the tourist taps "Add New Landmark" /
/// "View Details" (or, for signboard/stall/additional-food capture,
/// "Confirm") - see `FoodRecognitionViewModel.proceedToAddLandmark` etc.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
///
/// Build the layout from the Figma frame for this screen, using
/// `Theme.of(context)` and the tokens in `lib/app/theme/`. Reusable pieces go
/// in `food_recognition_view/widgets/`.
class FoodRecognitionView extends StatefulWidget {
  const FoodRecognitionView({super.key});

  @override
  State<FoodRecognitionView> createState() => _FoodRecognitionViewState();
}

class _FoodRecognitionViewState extends State<FoodRecognitionView>
    with WidgetsBindingObserver {
  late final FoodRecognitionViewModel _viewModel;

  CameraController? _cameraController;
  bool _isCameraInitializing = true;
  String? _cameraError;
  bool _cameraOpenInProgress = false;

  /// The cameras this device/browser exposes, from `availableCameras()` - kept
  /// so the tourist can flip between front/back when more than one exists
  /// (REQ106_1). `cameras.first` is NOT trustworthy: browsers often enumerate
  /// the front (user) camera first, which is useless for photographing food.
  List<CameraDescription> _cameras = const <CameraDescription>[];

  /// Index into [_cameras] that [_cameraController] was opened with - the flip
  /// button advances it (wrapping) and re-opens the camera.
  int _activeCameraIndex = 0;

  /// Live digital-zoom factor (1.0 = no zoom). Applied to BOTH the on-screen
  /// preview (a scale on the live feed) and the captured crop (the framed
  /// region shrinks by 1/zoom), so what the tourist frames while zoomed is
  /// exactly what reaches Gemini. This is a crop on the captured photo rather
  /// than the camera plugin's native zoom, because the web build the tourist
  /// tests on does not support `setZoomLevel`.
  double _zoom = 1.0;

  static const double _minZoom = 1.0;
  static const double _maxZoom = 4.0;

  /// The zoom level when the current pinch gesture started - so the pinch
  /// adjusts relative to it rather than jittering from wherever it was.
  double _zoomAtPinchStart = 1.0;

  /// Whether the unfinished-submission notice is done for this push - it
  /// opens at most once, not on every rebuild (the add-landmark ask flow
  /// below marks it too: that flow already offers the saved drafts).
  bool _draftPromptShown = false;

  /// Whether a post-frame check for the notice is already queued - prevents
  /// stacking one callback per frame (see [_scheduleDraftPromptCheck]).
  bool _draftPromptCheckQueued = false;

  void _zoomBy(double delta) {
    final double next = _zoom.clamp(_minZoom, _maxZoom) + delta;
    final double clamped = next.clamp(_minZoom, _maxZoom).toDouble();
    if (clamped == _zoom) return;
    setState(() {
      _zoom = clamped;
    });
  }

  void _resetZoom() {
    if (_zoom == _minZoom) return;
    setState(() {
      _zoom = _minZoom;
    });
  }

  void _onZoomScaleStart(ScaleStartDetails details) {
    _zoomAtPinchStart = _zoom;
  }

  void _onZoomScaleUpdate(ScaleUpdateDetails details) {
    final double next = (_zoomAtPinchStart * details.scale)
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    if (next == _zoom) return;
    setState(() {
      _zoom = next;
    });
  }

  /// The size of the camera viewfinder area, captured during layout - the
  /// frame guide is drawn against this, and `_cropToFrame` needs it to map
  /// the guide rectangle into the captured photo's pixel space.
  Size? _viewfinderSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Portrait-only capture, locked BEFORE the camera opens so the session
    // binds in portrait: both `_CameraViewfinder`'s sizing and `_cropToFrame`
    // assume a portrait preview, and a user who rotates the phone mid-shot
    // would otherwise get a preview that no longer matches the frame guide
    // they were aiming with. `dispose` gives rotation back to the OS.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);

    _viewModel = FoodRecognitionViewModel();

    // Which purpose this push is for (food / additional food / signboard /
    // stall) arrives through the hand-off, since routes carry no arguments.
    // Set it BEFORE onInit() - same pattern AddLandmarkView uses for the
    // recognized food itself. For an additional-food / signboard / stall
    // capture the first food's location also arrives, so this new capture
    // can be checked against it (50 m same-restaurant rule).
    _viewModel.setPurpose(LandmarkDraftHandoff().takePurpose());
    _viewModel.setReferenceLocation(
      LandmarkDraftHandoff().takeReferenceLocation(),
    );
    // The dishes the form (for an additional-food capture) already holds -
    // a re-captured duplicate is blocked on THIS screen instead of being
    // bounced back with a notice.
    _viewModel.setExistingFormFoods(
      LandmarkDraftHandoff().takeExistingFormFoods(),
    );
    _viewModel.onInit();

    _initCamera();
  }

  Future<void> _initCamera() async {
    // Android 6+/iOS need the OS camera permission before the live preview
    // can open. Request it explicitly - routed through the ViewModel's
    // facade chain, where the repository is the only thing that touches
    // `permission_handler` - instead of relying on the CameraException that
    // initialize() would otherwise surface. This View still owns the
    // CameraController directly (REQ106_1), but the permission check itself
    // stays out of the View.
    final bool cameraGranted = await _viewModel.requestCameraPermission();
    if (!cameraGranted) {
      if (mounted) {
        setState(() {
          _cameraError =
              'Camera permission is needed to capture photos. Enable it in '
              'Settings and try again.';
          _isCameraInitializing = false;
        });
      }
      return;
    }

    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera found on this device.';
            _isCameraInitializing = false;
          });
        }
        return;
      }

      _cameras = cameras;
      // Food photography needs the rear/environment lens, but browsers often
      // enumerate the front (user) camera first - so prefer back/external
      // instead of blindly taking `cameras.first`. The flip button then lets
      // the tourist move between them.
      final int rear = cameras.indexWhere(
        (CameraDescription c) =>
            c.lensDirection == CameraLensDirection.back ||
            c.lensDirection == CameraLensDirection.external,
      );
      _activeCameraIndex = rear < 0 ? 0 : rear;
      await _openCamera(cameras[_activeCameraIndex]);
    } on CameraException {
      if (mounted) {
        setState(() {
          _cameraError =
              'Unable to access the camera. Check camera permission in Settings.';
          _isCameraInitializing = false;
        });
      }
    }
  }

  /// Initialises [camera] into [_cameraController]. Shared by [_initCamera]
  /// and [_switchCamera] so flipping never duplicates the error handling.
  Future<void> _openCamera(CameraDescription camera) async {
    if (_cameraOpenInProgress) return;
    _cameraOpenInProgress = true;
    final CameraController controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false, // Stills only - no microphone permission needed.
    );
    try {
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
    } on CameraException {
      _cameraOpenInProgress = false;
      await controller.dispose();
      if (mounted) {
        setState(() {
          _cameraError =
              'Unable to access the camera. Check camera permission in Settings.';
          _isCameraInitializing = false;
        });
      }
      return;
    }
    if (!mounted) {
      _cameraOpenInProgress = false;
      await controller.dispose();
      return;
    }
    setState(() {
      _cameraController = controller;
      _isCameraInitializing = false;
      _cameraError = null;
    });
    _cameraOpenInProgress = false;
  }

  /// Flips between the front/back cameras when the device exposes more than
  /// one (REQ106_1). The camera plugin has no "switch lens" call, so a flip is
  /// a release of the current controller and a re-open of the next one.
  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final CameraController? old = _cameraController;
    if (!mounted) return;
    setState(() {
      _isCameraInitializing = true;
      // A different lens has a different field of view - start it un-zoomed.
      _zoom = _minZoom;
    });
    await old?.dispose();
    _cameraController = null;
    _activeCameraIndex = (_activeCameraIndex + 1) % _cameras.length;
    await _openCamera(_cameras[_activeCameraIndex]);
  }

  /// Whether the flip (front/back) button should show: only when more than
  /// one camera exists AND the current one is actually live (not while
  /// initialising, not on an error screen).
  bool get _canFlipCamera =>
      _cameras.length > 1 &&
      _cameraController != null &&
      _cameraController!.value.isInitialized;

  /// Whether pinch/button zoom is available: the live camera is up (no
  /// initialising spinner, no error screen, no frozen shot behind a popup).
  bool get _canZoom =>
      _cameraController != null &&
      _cameraController!.value.isInitialized &&
      _cameraError == null;

  // The camera plugin no longer manages lifecycle transitions itself (as of
  // v0.5.0) - the app is responsible for releasing/reacquiring the camera.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final CameraController? controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) return;
      controller.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitializing = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty) {
        _openCamera(_cameras[_activeCameraIndex]);
      } else {
        _initCamera();
      }
    }
  }

  Future<void> _focusCamera(Offset position, Size previewSize) async {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final Offset point = Offset(
      (position.dx / previewSize.width).clamp(0.0, 1.0),
      (position.dy / previewSize.height).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setFocusPoint(point);
    } on CameraException {
      // Some web cameras expose no manual focus point; auto focus remains set.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Release the portrait lock. The empty list is the documented "defer to
    // the operating system default" - the rest of the app has always been
    // free to rotate, and only this capture screen constrains it.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    _cameraController?.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _capture(FoodRecognitionViewModel viewModel) async {
    final CameraController? controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    final XFile image = await controller.takePicture();

    // EVERY purpose crops to its on-screen frame guide before analysis. The
    // guide is only a visual overlay - Gemini never sees it - so without
    // cropping, whatever sits outside the frame is still sent and still
    // judged. For food that meant the guide was purely decorative: nearby
    // dishes, table clutter and packaging all reached Gemini, inflating
    // `foodCount` ("please capture only one food") and giving it competing
    // subjects to identify. Cropping makes what the tourist framed the same
    // as what is actually analysed.
    final XFile framed = await _cropToFrame(
      image,
      _frameFactorsFor(viewModel.purpose),
      zoom: _zoom,
    );

    switch (viewModel.purpose) {
      case FoodRecognitionPurpose.food:
      case FoodRecognitionPurpose.additionalFood:
        await viewModel.captureAndRecognize(framed);
      case FoodRecognitionPurpose.signboard:
        await viewModel.captureSignboard(framed);
      case FoodRecognitionPurpose.stall:
        await viewModel.captureStallImage(framed);
    }
  }

  /// Crops [image] to the on-screen frame guide described by [factors] (the
  /// same width/height factors `_CameraViewfinder` uses to draw the guide).
  ///
  /// Maps the guide rectangle from the viewfinder, through the preview's
  /// `BoxFit.cover` scaling, into the captured photo's pixel space, then
  /// re-encodes just that region. Anything outside the guide is removed, so
  /// a signboard/stall captured outside the frame comes back clipped and
  /// Gemini reports it as `partially_captured`.
  Future<XFile> _cropToFrame(
    XFile image,
    ({double width, double height}) factors, {
    double zoom = 1.0,
  }) async {
    final Uint8List bytes = await image.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;
    final int pw = src.width;
    final int ph = src.height;

    // Viewfinder area the guide is drawn against (captured during layout).
    final Size vf = _viewfinderSize ?? Size(pw.toDouble(), ph.toDouble());

    // Preview's natural portrait size (swapped - see `_CameraViewfinder`).
    final Size preview =
        _cameraController?.value.previewSize ?? const Size(1, 1);
    final double wp = preview.height;
    final double hp = preview.width;

    // How `FittedBox(fit: cover)` scaled the preview into the viewfinder.
    final double scale = math.max(vf.width / wp, vf.height / hp);
    final double ox = (vf.width - wp * scale) / 2;
    final double oy = (vf.height - hp * scale) / 2;

    // Guide rect in viewfinder coords (centred). Digital zoom shrinks the
    // effective guide: 1x captures the whole base frame guide; 2x captures
    // the central half of it (which is what the zoomed preview shows under
    // the same on-screen guide) - so the shot matches the framing.
    final double effectiveWidth = (factors.width / zoom).clamp(0.0, 1.0);
    final double effectiveHeight = (factors.height / zoom).clamp(0.0, 1.0);
    final double gx0 = vf.width * (1 - effectiveWidth) / 2;
    final double gx1 = vf.width * (1 + effectiveWidth) / 2;
    final double gy0 = vf.height * (1 - effectiveHeight) / 2;
    final double gy1 = vf.height * (1 + effectiveHeight) / 2;

    // Viewfinder -> preview coords.
    final double px0 = (gx0 - ox) / scale;
    final double px1 = (gx1 - ox) / scale;
    final double py0 = (gy0 - oy) / scale;
    final double py1 = (gy1 - oy) / scale;

    // Preview -> photo pixels.
    final double x0 = (px0 * pw / wp).clamp(0, pw.toDouble());
    final double x1 = (px1 * pw / wp).clamp(0, pw.toDouble());
    final double y0 = (py0 * ph / hp).clamp(0, ph.toDouble());
    final double y1 = (py1 * ph / hp).clamp(0, ph.toDouble());
    final Rect crop = Rect.fromLTRB(x0, y0, x1, y1);

    if (crop.width <= 0 || crop.height <= 0) {
      src.dispose();
      codec.dispose();
      return image; // Degenerate crop - fall back to the original photo.
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      crop,
      Rect.fromLTWH(0, 0, crop.width, crop.height),
      Paint(),
    );
    final ui.Image cropped = await recorder.endRecording().toImage(
      crop.width.round(),
      crop.height.round(),
    );
    final ByteData? data = await cropped.toByteData(
      format: ui.ImageByteFormat.png,
    );
    cropped.dispose();
    src.dispose();
    codec.dispose();
    if (data == null) return image; // Re-encode failed - keep the original.

    return XFile.fromData(
      data.buffer.asUint8List(),
      mimeType: 'image/png',
      name: 'framed_${image.name}',
    );
  }

  /// All four purposes are part of the same "Add New Landmark" journey
  /// (see UC500_IMPLEMENTATION_GUIDE.md) - the title stays this one, fixed
  /// string throughout rather than switching per purpose, so the tourist
  /// always sees which overall task they're in the middle of. Only the
  /// on-screen instruction (see [_instructionFor]) varies by purpose -
  /// that one genuinely needs to, since it tells them what to do on THIS
  /// specific step, not which journey they're in.
  String _titleFor(FoodRecognitionPurpose purpose) => 'Add New Landmark';

  String _instructionFor(FoodRecognitionPurpose purpose) {
    switch (purpose) {
      case FoodRecognitionPurpose.food:
      case FoodRecognitionPurpose.additionalFood:
        return 'Position one local food in the frame';
      case FoodRecognitionPurpose.signboard:
        return 'Position the restaurant signboard in the frame';
      case FoodRecognitionPurpose.stall:
        return 'Position the whole stall in the frame';
    }
  }

  /// A food item, a signboard and a stall are physically different-shaped
  /// subjects - one fixed frame guide doesn't suit all three. See
  /// `AppLayoutRatios`'s doc for why each shape is what it is.
  ({double width, double height}) _frameFactorsFor(
    FoodRecognitionPurpose purpose,
  ) {
    switch (purpose) {
      case FoodRecognitionPurpose.food:
      case FoodRecognitionPurpose.additionalFood:
        return (
          width: AppLayoutRatios.foodFrameWidthFactor,
          height: AppLayoutRatios.foodFrameHeightFactor,
        );
      case FoodRecognitionPurpose.signboard:
        return (
          width: AppLayoutRatios.signboardFrameWidthFactor,
          height: AppLayoutRatios.signboardFrameHeightFactor,
        );
      case FoodRecognitionPurpose.stall:
        return (
          width: AppLayoutRatios.stallFrameWidthFactor,
          height: AppLayoutRatios.stallFrameHeightFactor,
        );
    }
  }

  bool _hasResult(FoodRecognitionViewModel viewModel) {
    switch (viewModel.purpose) {
      case FoodRecognitionPurpose.food:
      case FoodRecognitionPurpose.additionalFood:
        return viewModel.recognizedFood != null || viewModel.hasMultipleResults;
      case FoodRecognitionPurpose.signboard:
      case FoodRecognitionPurpose.stall:
        return viewModel.capturedImage != null;
    }
  }

  /// "Add New Landmark" reminder: before the form opens, the tourist must
  /// acknowledge that a landmark has to be added while they are at the
  /// restaurant - a form started far away cannot be completed (they can
  /// still save it as an incomplete submission and finish it on a later
  /// visit). Only the explicit acknowledgement continues; dismissing the
  /// dialog leaves them on this screen.
  ///
  /// After the acknowledgement, a saved draft holding the SAME dish and the
  /// SAME variant at this spot is offered for continuing - "Continue
  /// submission" reopens it pre-filled, "Start a new one" falls through to
  /// the fresh form. See `FoodRecognitionViewModel.draftToContinue`.
  Future<void> _proceedToAddLandmarkWithReminder(
    FoodRecognitionViewModel viewModel,
  ) async {
    // This flow itself offers the saved drafts (continue / start new), so the
    // reminder notice must not pop up behind it - it would fire the moment
    // the reminder dialog closes, mid-flow.
    _draftPromptShown = true;
    final bool acknowledged = await showAddLandmarkReminderDialog(context);
    if (!acknowledged || !mounted) return;
    final LandmarkDraft? draft = await viewModel.draftToContinue();
    if (!mounted) return;
    if (draft != null) {
      final bool continues = await showContinueDraftDialog(
        context,
        dishLabel: continueDraftDishLabel(draft),
        restaurantName: draft.restaurantName,
      );
      if (!mounted) return;
      if (continues) {
        viewModel.openDraft(draft);
        return;
      }
    }
    viewModel.proceedToAddLandmark();
  }

  /// Queues the one-shot check behind [_askAboutPendingDrafts]: once a
  /// fresh-capture push knows there are saved incomplete submissions, remind
  /// the tourist they can continue one from the Profile screen.
  ///
  /// The drafts load asynchronously after `initState`, so the check RE-ARMS
  /// itself until it has fired or is no longer needed. It also fires only
  /// while THIS screen is the one on top: a camera with the Add-Landmark form
  /// pushed above it is still mounted and still rebuilds, so a late drafts
  /// read used to pop "You have N unfinished submissions" over that form
  /// while the tourist was typing in a field - a notice nothing they did had
  /// asked for. With a form (or one of this screen's own dialogs) in front,
  /// the check simply waits: the reminder belongs to the moment the camera is
  /// genuinely in front again.
  void _scheduleDraftPromptCheck() {
    if (_draftPromptCheckQueued || _draftPromptShown) return;
    _draftPromptCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _draftPromptCheckQueued = false;
      if (!mounted || _draftPromptShown) return;
      if (_viewModel.purpose != FoodRecognitionPurpose.food) return;
      // A route above this one owns the screen right now (the form, or one
      // of this screen's dialogs) - keep waiting instead of firing over it.
      if (ModalRoute.of(context)?.isCurrent != true ||
          _viewModel.pendingDrafts.isEmpty) {
        _scheduleDraftPromptCheck();
        return;
      }
      _draftPromptShown = true;
      _askAboutPendingDrafts(_viewModel);
    });
  }

  /// Coming back to the camera REMINDS the tourist about a saved incomplete
  /// submission: it points them at the Profile screen's Incomplete
  /// Submissions list, where they can continue (or delete) it themselves.
  /// Nothing is decided here - the notice has a single acknowledgement, so
  /// the draft is simply left waiting. Shown once per push, and only when
  /// this push is a fresh food capture - never while an additional food /
  /// signboard / stall capture is in progress.
  Future<void> _askAboutPendingDrafts(
    FoodRecognitionViewModel viewModel,
  ) async {
    // This screen can sit under a form for a while, so the list loaded at
    // initState may be stale - name what is really waiting.
    await viewModel.refreshPendingDrafts();
    if (!mounted) return;
    final List<LandmarkDraft> drafts = viewModel.pendingDrafts;
    if (drafts.isEmpty) return;
    await showUnfinishedSubmissionDialog(
      context,
      restaurantName: drafts.first.restaurantName,
      draftCount: drafts.length,
    );
  }

  Widget _buildPopupContent(FoodRecognitionViewModel viewModel) {
    if (viewModel.isProcessing) {
      return const _LoadingState();
    }

    if (viewModel.recognitionError != null) {
      return _ErrorState(message: viewModel.recognitionError!);
    }

    // Gemini was unsure between a few likely dishes (A5) - show the top-3
    // picker; the single-result card below only renders once the tourist has
    // chosen (or the quick call was confident).
    if (viewModel.hasMultipleResults) {
      return MultipleResultsCard(
        results: viewModel.multipleResults,
        onSelect: viewModel.selectFromMultiple,
        onEnterName: viewModel.enterFoodName,
        foodNameMaxLength: viewModel.foodNameMaxLength,
        foodNameWarning: viewModel.foodNameWarning,
        isProcessing: viewModel.isProcessing,
      );
    }

    switch (viewModel.purpose) {
      case FoodRecognitionPurpose.food:
        // At sea / outside Malaysia (A9) the recognised food is still shown
        // (the tourist can keep recognising) but "Add New Landmark" is not
        // offered - a new landmark may only be added on Malaysian land.
        final bool canAddFood =
            viewModel.isLocalFood && viewModel.fitsCatalogueCategory;
        final String? locationBlock = canAddFood
            ? viewModel.addLandmarkLocationBlockMessage
            : null;
        return RecognitionResultCard(
          food: viewModel.recognizedFood!,
          variant: viewModel.variant,
          capturedImage: viewModel.capturedImage,
          isLocalFood: viewModel.isLocalFood,
          fitsCatalogueCategory: viewModel.fitsCatalogueCategory,
          isLowConfidence: viewModel.isLowConfidence,
          nameMismatch: viewModel.nameMismatch,
          typedName: viewModel.typedName,
          typoNotice: viewModel.typedNameTypoNotice,
          dietaryConflicts: viewModel.dietaryConflicts,
          onDismissNameMismatch: viewModel.dismissNameMismatch,
          onViewDetails: viewModel.proceedToViewDetails,
          // Non-addable (not local, a Malaysian snack/package, or the fix is
          // at sea / outside Malaysia): details + "View Details" stay, but
          // there is no "Add New Landmark". The reminder dialog must be
          // acknowledged before the form opens.
          onAddLandmark: canAddFood && locationBlock == null
              ? () => _proceedToAddLandmarkWithReminder(viewModel)
              : null,
          onEnterName: viewModel.enterFoodName,
          foodNameMaxLength: viewModel.foodNameMaxLength,
          foodNameWarning: viewModel.foodNameWarning,
          isProcessing: viewModel.isProcessing,
          promptText:
              locationBlock ??
              (canAddFood
                  ? 'Would you like to add this as a new landmark?'
                  : !viewModel.isLocalFood
                  ? "This doesn't appear to be Malaysian local food, so it "
                        "can't be added as a landmark."
                  : 'This is a Malaysian product but it is a snack or packaged '
                        "item, so it can't be added."),
        );

      case FoodRecognitionPurpose.additionalFood:
        return RecognitionResultCard(
          food: viewModel.recognizedFood!,
          variant: viewModel.variant,
          capturedImage: viewModel.capturedImage,
          isLocalFood: viewModel.isLocalFood,
          fitsCatalogueCategory: viewModel.fitsCatalogueCategory,
          isLowConfidence: viewModel.isLowConfidence,
          nameMismatch: viewModel.nameMismatch,
          typedName: viewModel.typedName,
          typoNotice: viewModel.typedNameTypoNotice,
          dietaryConflicts: viewModel.dietaryConflicts,
          onDismissNameMismatch: viewModel.dismissNameMismatch,
          // Same "View Details" as the primary capture; the detail screen's
          // confirm then returns this food to the existing form (see
          // LandmarkDetailViewModel.returnToFormAsAdditionalFood) rather
          // than pushing a brand-new AddLandmarkView.
          onViewDetails: viewModel.proceedToViewDetails,
          // Non-addable food: never "Add to Landmark" back onto the form.
          // Also blocked when this second food was captured more than 50 m
          // from the first food - it is not the same restaurant - or when
          // the dish is ALREADY on the form (the same duplicate rule the
          // form applies), in which case the reason is shown below instead
          // of bouncing the tourist back with a notice.
          onAddLandmark:
              viewModel.isLocalFood &&
                  viewModel.fitsCatalogueCategory &&
                  !viewModel.isCaptureOutOfRange &&
                  viewModel.duplicateFormFoodBlockMessage == null
              ? viewModel.confirmFoodAndReturn
              : null,
          onEnterName: viewModel.enterFoodName,
          foodNameMaxLength: viewModel.foodNameMaxLength,
          foodNameWarning: viewModel.foodNameWarning,
          isProcessing: viewModel.isProcessing,
          addLandmarkLabel: 'Add to Landmark',
          blockMessage:
              viewModel.captureRangeError ??
              viewModel.duplicateFormFoodBlockMessage,
          // Blocked (out of range, or already on the form): the warning box
          // above already carries the reason AND the action - a prompt line
          // here would only repeat it.
          promptText:
              viewModel.captureRangeError != null ||
                  viewModel.duplicateFormFoodBlockMessage != null
              ? null
              : (viewModel.isLocalFood && viewModel.fitsCatalogueCategory
                    ? '                 Add this food to the landmark?'
                    : !viewModel.isLocalFood
                    ? "This doesn't appear to be Malaysian local food, so it "
                          "can't be added."
                    : 'This is a Malaysian product but it is a snack or packaged '
                          "item, so it can't be added."),
        );

      case FoodRecognitionPurpose.signboard:
      case FoodRecognitionPurpose.stall:
        return _ImageCaptureConfirm(
          purpose: viewModel.purpose,
          extractedRestaurantName: viewModel.extractedRestaurantName,
          // Too far from the first food (50 m): not this restaurant's
          // signboard/stall - no confirm, capture again instead.
          onConfirm: viewModel.isCaptureOutOfRange
              ? null
              : viewModel.confirmCaptureAndReturn,
          blockMessage: viewModel.captureRangeError,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // _viewModel.purpose is set synchronously in initState(), before this
    // first build ever runs, and never changes afterwards - safe to read
    // directly here rather than through Consumer.
    final bool cameraReady =
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        _cameraError == null;

    // One-shot: once a fresh-capture push knows there are saved incomplete
    // submissions, remind the tourist they can continue one from the Profile
    // screen (see [_askAboutPendingDrafts]). The drafts load asynchronously
    // after initState, so the check re-arms itself until it has fired.
    _scheduleDraftPromptCheck();

    return ChangeNotifierProvider<FoodRecognitionViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: AppTopBar(
          title: _titleFor(_viewModel.purpose),
          actions: <Widget>[
            // Presenter tool (dev builds, Android only): teleports or nudges
            // the GPS so a demo can "walk" in and out of the 50 m
            // same-restaurant range between captures without moving the
            // device - same singleton the dashboard drives.
            //
            // This button lives in the APP BAR, outside the body's Consumer,
            // so it needs its own Consumer: the mock's live state (`isActive`)
            // and the fix its "walk 60 m" chips move FROM (`currentLocation`)
            // change whenever a mock is set. Without listening they stayed
            // frozen at their first-build values - the picker kept showing
            // "Current fix" with no "Stop mock", and a second nudge moved
            // from the ORIGINAL fix instead of the mocked one, so
            // "North then South" never returned to the start.
            if (Env.appEnv != 'prod' && _viewModel.mockGpsSupported)
              Consumer<FoodRecognitionViewModel>(
                builder:
                    (
                      BuildContext context,
                      FoodRecognitionViewModel viewModel,
                      Widget? _,
                    ) => MockGpsButton(
                      isActive: viewModel.mockGpsActive,
                      onSetMock: (double latitude, double longitude) =>
                          viewModel.setMockGps(
                            latitude: latitude,
                            longitude: longitude,
                          ),
                      onStopMock: viewModel.stopMockGps,
                      fromLocation: viewModel.currentLocation,
                    ),
              ),
          ],
        ),
        body: Consumer<FoodRecognitionViewModel>(
          builder:
              (
                BuildContext context,
                FoodRecognitionViewModel viewModel,
                Widget? _,
              ) {
                final bool showPopup =
                    viewModel.isProcessing ||
                    viewModel.recognitionError != null ||
                    _hasResult(viewModel);

                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // Camera view fills the space between the app bar and the
                    // capture bar - the button lives below it, not floating on
                    // top of the live feed. Once something's captured, the
                    // viewfinder shows that frozen photo instead of the live
                    // feed, until the popup's X closes it (clearAndRetry) and
                    // the live feed resumes.
                    Column(
                      children: <Widget>[
                        Expanded(
                          child: LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  // Record the area the frame guide is drawn
                                  // against, so `_cropToFrame` can map the guide
                                  // into the captured photo.
                                  _viewfinderSize = constraints.biggest;
                                  // Pinch to zoom in/out on the live feed;
                                  // double-tap resets to 1x. Buttons (in the
                                  // capture bar) do the same for pointer
                                  // devices without touch.
                                  return GestureDetector(
                                    onScaleStart: _onZoomScaleStart,
                                    onScaleUpdate: _onZoomScaleUpdate,
                                    onTapDown: (TapDownDetails details) =>
                                        _focusCamera(
                                          details.localPosition,
                                          constraints.biggest,
                                        ),
                                    onDoubleTap: _resetZoom,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: <Widget>[
                                        _CameraViewfinder(
                                          controller: _cameraController,
                                          isInitializing: _isCameraInitializing,
                                          error: _cameraError,
                                          instruction: _instructionFor(
                                            viewModel.purpose,
                                          ),
                                          frameFactors: _frameFactorsFor(
                                            viewModel.purpose,
                                          ),
                                          frozenImage: viewModel.capturedImage,
                                          zoom: _zoom,
                                        ),
                                        // Front/back flip - only when the
                                        // device exposes more than one camera
                                        // and the current one is live
                                        // (REQ106_1). Bottom-right keeps it
                                        // clear of the instruction pill at
                                        // the top and of every purpose's
                                        // frame guide.
                                        if (_canFlipCamera)
                                          Positioned(
                                            bottom: AppSpacing.md,
                                            right: AppSpacing.md,
                                            child: _CameraFlipButton(
                                              onFlip: _switchCamera,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                          ),
                        ),
                        _CaptureControlBar(
                          onCapture: cameraReady
                              ? () => _capture(viewModel)
                              : null,
                          // Zoom in/out buttons - active only while the live
                          // camera is up (the frozen shot behind the popup
                          // can't be zoomed further).
                          zoom: _canZoom ? _zoom : null,
                          onZoomIn: _canZoom ? () => _zoomBy(0.5) : null,
                          onZoomOut: _canZoom ? () => _zoomBy(-0.5) : null,
                        ),
                      ],
                    ),
                    if (showPopup)
                      _PopupOverlay(
                        onClose: viewModel.isProcessing
                            ? null
                            : viewModel.clearAndRetry,
                        child: _buildPopupContent(viewModel),
                      ),
                  ],
                );
              },
        ),
      ),
    );
  }
}

/// The camera area (REQ106_1): either the live in-app feed with a frame
/// overlay, or - once [frozenImage] is set - that captured photo instead,
/// dimmed by the popup's scrim on top of it. Not a functional crop - the
/// frame is just a visual alignment aid, same as every other in-app camera
/// UI. Fills the space between the app bar and the capture bar - see
/// [_CaptureControlBar], which lives below it rather than floating on top.
class _CameraViewfinder extends StatelessWidget {
  const _CameraViewfinder({
    required this.controller,
    required this.isInitializing,
    required this.error,
    required this.instruction,
    required this.frameFactors,
    required this.frozenImage,
    this.zoom = 1.0,
  });

  final CameraController? controller;
  final bool isInitializing;
  final String? error;
  final String instruction;

  /// Live digital-zoom factor (1.0 = no zoom) - scales the live feed about
  /// its centre so the tourist sees the closer view before capturing. The
  /// frame guide overlay is NOT scaled: it stays at its normal screen size,
  /// which under zoom corresponds to a smaller central region of the photo -
  /// exactly the region `FoodRecognitionView._cropToFrame` captures.
  final double zoom;

  /// Width/height of the frame guide, as a fraction of this viewfinder's
  /// own size - see `FoodRecognitionView._frameFactorsFor`, which picks the
  /// shape for the current capture purpose (food/signboard/stall each get
  /// a different one).
  final ({double width, double height}) frameFactors;

  /// The just-captured photo. While this is set, it replaces the live feed
  /// entirely (frame guide and instruction included - there's nothing left
  /// to frame once a shot has been taken).
  final XFile? frozenImage;

  @override
  Widget build(BuildContext context) {
    if (frozenImage != null) {
      return ColoredBox(
        color: AppColors.cameraBackground,
        child: _FrozenImage(image: frozenImage!),
      );
    }

    if (error != null) {
      return ColoredBox(
        color: AppColors.cameraBackground,
        child: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),
      );
    }

    final CameraController? camera = controller;
    if (isInitializing || camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: AppColors.cameraBackground,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.cameraBackground,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // `camera.value.aspectRatio` is reported in landscape/sensor
          // terms, not portrait-display terms, so `previewSize` is swapped
          // (height/width, not width/height) below to get the correct
          // natural shape for a portrait preview - and the screen is locked
          // to portrait while it is open (see `_FoodRecognitionViewState`),
          // so this portrait assumption always holds. `FittedBox(fit: cover)`
          // then scales that up to fill this area, cropping any overflow -
          // the standard, framework-provided way to do this.
          Builder(
            builder: (BuildContext context) {
              final Size previewSize =
                  camera.value.previewSize ?? const Size(1, 1);
              return ClipRect(
                child: Transform.scale(
                  scale: zoom,
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: previewSize.height,
                      height: previewSize.width,
                      child: CameraPreview(camera),
                    ),
                  ),
                ),
              );
            },
          ),
          // Frame guide (REQ106_1: "capture a food image within a frame") -
          // shape varies by purpose, see [frameFactors].
          Center(
            child: FractionallySizedBox(
              widthFactor: frameFactors.width,
              heightFactor: frameFactors.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.onPrimary, width: 2),
                  borderRadius: AppRadius.cardRadius,
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.scrim,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  instruction,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The just-captured photo, filling the viewfinder area. The popup's own
/// scrim (painted on top, in [FoodRecognitionView]) is what dims it - this
/// widget just displays the image.
class _FrozenImage extends StatelessWidget {
  const _FrozenImage({required this.image});

  final XFile image;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: image.readAsBytes(),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      },
    );
  }
}

/// Dedicated control area below the viewfinder, holding the shutter button
/// (and, while the live camera is up, the zoom in/out buttons flanking it).
/// Kept separate from [_CameraViewfinder] so the controls never overlap the
/// live feed.
class _CaptureControlBar extends StatelessWidget {
  const _CaptureControlBar({
    required this.onCapture,
    this.zoom,
    this.onZoomIn,
    this.onZoomOut,
  });

  final VoidCallback? onCapture;

  /// Current zoom factor (non-null while zoom controls are active).
  final double? zoom;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  @override
  Widget build(BuildContext context) {
    final bool canZoom = zoom != null && onZoomIn != null && onZoomOut != null;
    return ColoredBox(
      color: AppColors.cameraBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (canZoom) ...<Widget>[
                  _ZoomButton(
                    icon: Icons.zoom_out,
                    label: 'Zoom out',
                    onTap: onZoomOut,
                  ),
                ],
                const SizedBox(width: AppSpacing.xl),
                _CaptureButton(onTap: onCapture),
                const SizedBox(width: AppSpacing.xl),
                if (canZoom) ...<Widget>[
                  _ZoomButton(
                    icon: Icons.zoom_in,
                    label: 'Zoom in',
                    onTap: onZoomIn,
                  ),
                ],
              ],
            ),
            if (canZoom)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '${zoom!.toStringAsFixed(1)}x',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small circular zoom in/out button flanking the shutter - an alternative to
/// pinch for pointer devices, and the only zoom affordance on desktop web.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.scrim,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: label,
          icon: Icon(icon, color: AppColors.onPrimary),
          onPressed: onTap,
        ),
      ),
    );
  }
}

/// Centred, circular capture button - matches the mock-up's orange camera FAB.
/// Dims and stops responding to taps while [onTap] is null (camera not ready
/// yet, still initialising, or a popup is covering the screen).
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      label: 'Capture photo',
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: AppSizes.navFabDiameter,
            height: AppSizes.navFabDiameter,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: AppColors.onPrimary, width: 3),
              ),
            ),
            child: const Icon(Icons.camera_alt, color: AppColors.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// Small circular control overlaid at the bottom-right of the live
/// viewfinder - flips between the front and back cameras when more than one is
/// available (REQ106_1). Hidden while the camera is initialising or errored.
class _CameraFlipButton extends StatelessWidget {
  const _CameraFlipButton({required this.onFlip});

  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Switch camera',
      child: Material(
        color: AppColors.scrim,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'Switch camera',
          icon: const Icon(
            Icons.flip_camera_android,
            color: AppColors.onPrimary,
          ),
          onPressed: onFlip,
        ),
      ),
    );
  }
}

/// Shared popup chrome for every post-capture state (loading, error, result,
/// image-capture-confirm) - a scrim over the frozen captured photo with a
/// centred white card, matching the mock-up. The close (X) button is the
/// only way back to the live camera - there's no separate "capture again" /
/// "retake" button in any individual state. Loading doesn't get one:
/// cancelling mid-analysis isn't supported.
class _PopupOverlay extends StatelessWidget {
  const _PopupOverlay({required this.child, this.onClose});

  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.scrim,
      alignment: const Alignment(
        0,
        AppLayoutRatios.popupVerticalOffset,
      ), // Slightly above centre.
      padding: AppSpacing.screenPadding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppSizes.dialogMaxWidth,
          maxHeight:
              MediaQuery.of(context).size.height *
              AppLayoutRatios.popupMaxHeightFraction,
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Stack(
              children: <Widget>[
                child,
                if (onClose != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: onClose,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          const Text('Analysing image...', style: AppTextStyles.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Recognition may take some time - please wait patiently.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error content. No retry button here - the popup's shared close (X)
/// returns to the live camera to try again.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.error_outline, color: AppColors.error, size: 40),
        const SizedBox(height: AppSpacing.md),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),
      ],
    );
  }
}

/// Shown after a successful signboard/stall capture. "Confirm" pops this
/// screen back to `AddLandmarkView` with the result; there's no separate
/// "retake" - the popup's shared close (X) covers that.
class _ImageCaptureConfirm extends StatelessWidget {
  const _ImageCaptureConfirm({
    required this.purpose,
    required this.extractedRestaurantName,
    required this.onConfirm,
    this.blockMessage,
  });

  final FoodRecognitionPurpose purpose;
  final String? extractedRestaurantName;

  /// Null when the capture cannot be confirmed - it was taken more than 50 m
  /// from the first food, so it is not this restaurant's signboard/stall.
  final VoidCallback? onConfirm;

  /// Why the capture cannot be confirmed (see [onConfirm]).
  final String? blockMessage;

  @override
  Widget build(BuildContext context) {
    final bool isSignboard = purpose == FoodRecognitionPurpose.signboard;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          blockMessage == null ? Icons.check_circle : Icons.location_off,
          color: blockMessage == null ? AppColors.success : AppColors.warning,
          size: 40,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          isSignboard ? 'Signboard captured' : 'Stall image captured',
          style: AppTextStyles.titleMedium,
        ),
        if (isSignboard && extractedRestaurantName != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Restaurant name: $extractedRestaurantName',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        if (blockMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            blockMessage!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.bannerCautionText,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        // When Confirm is withheld the block message above is the whole
        // story (reason + action) - no second line repeating "capture
        // again". The popup's shared close (X) is how the tourist leaves.
        if (onConfirm != null)
          ElevatedButton(onPressed: onConfirm, child: const Text('Confirm')),
      ],
    );
  }
}
