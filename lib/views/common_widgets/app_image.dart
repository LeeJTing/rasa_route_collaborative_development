import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Displays bundled Figma assets and remote images through one safe widget.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.semanticLabel,
    this.fallback,
    this.decodeWidth,
  });

  final String? source;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final String? semanticLabel;
  final Widget? fallback;

  /// Decode the image at this width in **logical** pixels instead of at its
  /// full resolution.
  ///
  /// Flutter decodes a network image at whatever size it arrives and keeps that
  /// bitmap in the image cache, however small the frame drawing it is. A
  /// 426x240 photo in a 102pt frame is four times the pixels the screen can
  /// show, decoded on the UI thread and held in memory for every card on
  /// screen. This scales by the device pixel ratio, so it asks for the pixels
  /// the display actually has and no more.
  ///
  /// Leave it null where the image is shown at full size.
  final int? decodeWidth;

  @override
  Widget build(BuildContext context) {
    final String value = source?.trim() ?? '';
    final Widget effectiveFallback =
        fallback ??
        const ColoredBox(
          color: AppColors.surfaceVariant,
          child: Center(
            child: Icon(Icons.restaurant, color: AppColors.textSecondary),
          ),
        );
    final Uri? networkUri = Uri.tryParse(value);
    final bool isNetworkImage =
        networkUri != null &&
        (networkUri.scheme == 'http' || networkUri.scheme == 'https') &&
        networkUri.host.isNotEmpty;
    final int? cacheWidth = decodeWidth == null
        ? null
        : (decodeWidth! * MediaQuery.devicePixelRatioOf(context)).round();

    final Widget image = value.isEmpty
        ? effectiveFallback
        : value.startsWith('assets/')
        ? Image.asset(
            value,
            fit: fit,
            cacheWidth: cacheWidth,
            semanticLabel: semanticLabel,
            errorBuilder: (_, _, _) => effectiveFallback,
          )
        : isNetworkImage
        ? Image.network(
            value,
            fit: fit,
            cacheWidth: cacheWidth,
            semanticLabel: semanticLabel,
            loadingBuilder: (_, Widget child, ImageChunkEvent? progress) =>
                progress == null ? child : effectiveFallback,
            errorBuilder: (_, _, _) => effectiveFallback,
          )
        : effectiveFallback;
    return ClipRRect(borderRadius: borderRadius, child: image);
  }
}
