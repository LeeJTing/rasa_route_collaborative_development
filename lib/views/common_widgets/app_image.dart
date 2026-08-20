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
  });

  final String? source;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final String value = source ?? '';
    final Widget fallback = const ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(Icons.restaurant, color: AppColors.textSecondary),
      ),
    );
    final Widget image = value.isEmpty
        ? fallback
        : value.startsWith('assets/')
        ? Image.asset(
            value,
            fit: fit,
            semanticLabel: semanticLabel,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.network(
            value,
            fit: fit,
            semanticLabel: semanticLabel,
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRRect(borderRadius: borderRadius, child: image);
  }
}
