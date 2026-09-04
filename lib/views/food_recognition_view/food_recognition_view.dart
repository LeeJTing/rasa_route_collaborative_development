import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../view_models/food_recognition_view_model.dart';
import '../common_widgets/app_top_bar.dart';
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

  /// The size of the camera viewfinder area, captured during layout - the
  /// frame guide is drawn against this, and `_cropToFrame` needs it to map
  /// the guide rectangle into the captured photo's pixel space.
  Size? _viewfinderSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _viewModel = FoodRecognitionViewModel();

    // Which purpose this push is for (food / additional food / signboard /
    // stall) arrives through the hand-off, since routes carry no arguments.
    // Set it BEFORE onInit() - same pattern AddLandmarkView uses for the
    // recognized food itself.
    _viewModel.setPurpose(LandmarkDraftHandoff().takePurpose());
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

      final CameraController controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false, // Stills only - no microphone permission needed.
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraInitializing = false;
      });
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

  // The camera plugin no longer manages lifecycle transitions itself (as of
  // v0.5.0) - the app is responsible for releasing/reacquiring the camera.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    ({double width, double height}) factors,
  ) async {
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

    // Guide rect in viewfinder coords (centred).
    final double gx0 = vf.width * (1 - factors.width) / 2;
    final double gx1 = vf.width * (1 + factors.width) / 2;
    final double gy0 = vf.height * (1 - factors.height) / 2;
    final double gy1 = vf.height * (1 + factors.height) / 2;

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
        isProcessing: viewModel.isProcessing,
      );
    }

    switch (viewModel.purpose) {
      case FoodRecognitionPurpose.food:
        return RecognitionResultCard(
          food: viewModel.recognizedFood!,
          capturedImage: viewModel.capturedImage,
          isLocalFood: viewModel.isLocalFood,
          fitsCatalogueCategory: viewModel.fitsCatalogueCategory,
          isLowConfidence: viewModel.isLowConfidence,
          nameMismatch: viewModel.nameMismatch,
          observedFoodName: viewModel.observedFoodName,
          typedName: viewModel.typedName,
          onDismissNameMismatch: viewModel.dismissNameMismatch,
          onViewDetails: viewModel.proceedToViewDetails,
          // Non-addable (not local, or a Malaysian snack/package): details +
          // "View Details" stay, but there is no "Add New Landmark".
          onAddLandmark:
              viewModel.isLocalFood && viewModel.fitsCatalogueCategory
              ? viewModel.proceedToAddLandmark
              : null,
          onEnterName: viewModel.enterFoodName,
          isProcessing: viewModel.isProcessing,
          promptText: viewModel.isLocalFood && viewModel.fitsCatalogueCategory
              ? 'Would you like to add this as a new landmark?'
              : !viewModel.isLocalFood
              ? "This doesn't appear to be Malaysian local food, so it "
                    "can't be added as a landmark."
              : 'This is a Malaysian product but it is a snack or packaged '
                    "item, so it can't be added.",
        );

      case FoodRecognitionPurpose.additionalFood:
        return RecognitionResultCard(
          food: viewModel.recognizedFood!,
          capturedImage: viewModel.capturedImage,
          isLocalFood: viewModel.isLocalFood,
          fitsCatalogueCategory: viewModel.fitsCatalogueCategory,
          isLowConfidence: viewModel.isLowConfidence,
          nameMismatch: viewModel.nameMismatch,
          observedFoodName: viewModel.observedFoodName,
          typedName: viewModel.typedName,
          onDismissNameMismatch: viewModel.dismissNameMismatch,
          // Same "View Details" as the primary capture; the detail screen's
          // confirm then returns this food to the existing form (see
          // LandmarkDetailViewModel.returnToFormAsAdditionalFood) rather
          // than pushing a brand-new AddLandmarkView.
          onViewDetails: viewModel.proceedToViewDetails,
          // Non-addable food: never "Add to Landmark" back onto the form.
          onAddLandmark:
              viewModel.isLocalFood && viewModel.fitsCatalogueCategory
              ? viewModel.confirmFoodAndReturn
              : null,
          onEnterName: viewModel.enterFoodName,
          isProcessing: viewModel.isProcessing,
          addLandmarkLabel: 'Add to Landmark',
          promptText: viewModel.isLocalFood && viewModel.fitsCatalogueCategory
              ? 'Add this food to the landmark?'
              : !viewModel.isLocalFood
              ? "This doesn't appear to be Malaysian local food, so it "
                    "can't be added."
              : 'This is a Malaysian product but it is a snack or packaged '
                    "item, so it can't be added.",
        );

      case FoodRecognitionPurpose.signboard:
      case FoodRecognitionPurpose.stall:
        return _ImageCaptureConfirm(
          purpose: viewModel.purpose,
          extractedRestaurantName: viewModel.extractedRestaurantName,
          onConfirm: viewModel.confirmCaptureAndReturn,
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

    return ChangeNotifierProvider<FoodRecognitionViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: AppTopBar(title: _titleFor(_viewModel.purpose)),
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
                                  return _CameraViewfinder(
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
                                  );
                                },
                          ),
                        ),
                        _CaptureControlBar(
                          onCapture: cameraReady
                              ? () => _capture(viewModel)
                              : null,
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
  });

  final CameraController? controller;
  final bool isInitializing;
  final String? error;
  final String instruction;

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
          // natural shape for a portrait preview. `FittedBox(fit: cover)`
          // then scales that up to fill this area, cropping any overflow -
          // the standard, framework-provided way to do this.
          Builder(
            builder: (BuildContext context) {
              final Size previewSize =
                  camera.value.previewSize ?? const Size(1, 1);
              return ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: previewSize.height,
                    height: previewSize.width,
                    child: CameraPreview(camera),
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

/// Dedicated control area below the viewfinder, holding the shutter button.
/// Kept separate from [_CameraViewfinder] so the button never overlaps the
/// live feed.
class _CaptureControlBar extends StatelessWidget {
  const _CaptureControlBar({required this.onCapture});

  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cameraBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: _CaptureButton(onTap: onCapture)),
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
  });

  final FoodRecognitionPurpose purpose;
  final String? extractedRestaurantName;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final bool isSignboard = purpose == FoodRecognitionPurpose.signboard;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.check_circle, color: AppColors.success, size: 40),
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
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(onPressed: onConfirm, child: const Text('Confirm')),
      ],
    );
  }
}
