import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'app_image.dart';

/// Shows a photo full-screen over a dark scrim, pinch/drag to zoom.
///
/// Same presentation the food-detail hero and the submitted-landmark card
/// already use (dark [AppColors.scrim] barrier, an [InteractiveViewer] capped
/// at 4x, a close button in the corner) - shared here so every "look at this
/// photo properly" overlay in the app behaves identically.
///
/// Pass ONE of:
///   * [file] - a photo still on this device (the tourist's own capture);
///   * [source] - a stored URL or bundled asset, the same values [AppImage]
///     takes (a photo that already lives in storage).
///
/// [semanticLabel] describes the photo for screen readers.
///
/// RULE (view layer): presentation only. The caller decides WHEN this is
/// appropriate (a tap on a thumbnail, see `RecognisedFoodCard.onImageTap`)
/// and owns where the photo comes from.
Future<void> showEnlargedImage(
  BuildContext context, {
  required String semanticLabel,
  XFile? file,
  String? source,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (BuildContext dialogContext) => Dialog(
    insetPadding: EdgeInsets.zero,
    backgroundColor: AppColors.transparent,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: _FullImage(
              file: file,
              source: source,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
        Positioned(
          top: AppSpacing.lg,
          right: AppSpacing.lg,
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Close image',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ),
        ),
      ],
    ),
  ),
);

/// Wraps a photo so the tourist can open it full-screen: the [child] and the
/// small "View photo" hint under it share ONE tap target, and the hint tells
/// them the photo can be opened at all - a photo with no other affordance
/// (the card's square crop, the form's cover-cropped restaurant photo) reads
/// as decoration otherwise.
///
/// The caller owns WHAT opens: pass `showEnlargedImage` (or the screen's own
/// equivalent) as [onTap]. [borderRadius] should match whatever clips the
/// photo, so the ripple follows the same corners.
class EnlargeablePhoto extends StatelessWidget {
  const EnlargeablePhoto({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sm)),
  });

  /// The photo itself - a thumbnail on the "Recognised Food" card, the
  /// full-width restaurant photo on the Add-Landmark form.
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: borderRadius,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        child,
        const SizedBox(height: AppSpacing.xs),
        // Styled like the app's other inline links ("View Details").
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.zoom_in, size: 16, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'View photo',
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The photo itself - shown `BoxFit.contain` so the WHOLE shot fits the
/// screen (the point of opening it here, rather than reading a cropped
/// thumbnail).
class _FullImage extends StatelessWidget {
  const _FullImage({this.file, this.source, required this.semanticLabel});

  final XFile? file;
  final String? source;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final XFile? file = this.file;
    if (file == null) {
      return AppImage(
        source: source,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
      );
    }
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        final Uint8List? bytes = snapshot.data;
        if (bytes == null) {
          return const CircularProgressIndicator();
        }
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          semanticLabel: semanticLabel,
          // A photo that cannot be decoded shows an icon, never the engine's
          // red error box (`AppImage` guards its own loads the same way).
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, color: AppColors.surface),
        );
      },
    );
  }
}
