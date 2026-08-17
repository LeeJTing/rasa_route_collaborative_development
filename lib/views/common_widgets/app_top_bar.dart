import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';

/// The app bar every screen uses.
///
/// Taken from the "App bar" component in the Figma mock-up: 81 high, cream
/// background, a 30px back chevron on the left and a centred title. The
/// mock-up has two variants — with a profile avatar on the right and without —
/// so this widget covers both through [profileImageUrl] / [onProfileTap], and
/// a general [actions] slot for anything else.
///
/// It implements [PreferredSizeWidget], so it drops straight into
/// `Scaffold(appBar: ...)`:
///
/// ```dart
/// Scaffold(
///   appBar: const AppTopBar(title: 'Prawn Noodle'),
///   body: ...,
/// )
/// ```
///
/// Like every widget in `common_widgets/`, it takes data and callbacks and
/// nothing else — it never reads a ViewModel.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.showBackButton,
    this.onBack,
    this.profileImageUrl,
    this.onProfileTap,
    this.actions = const <Widget>[],
    this.compact = false,
    this.backgroundColor,
  });

  /// Centred title. Keep it short — long titles are ellipsised, not wrapped.
  final String title;

  /// Optional second line under the title, e.g. a region or a category.
  final String? subtitle;

  /// Force the back chevron on or off. When null (the default) it is shown
  /// whenever there is something to pop, which is what you want almost always.
  final bool? showBackButton;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Shows the profile avatar on the right. Null hides it — that is the
  /// mock-up's "App bar no profile" variant.
  final String? profileImageUrl;

  /// Tapping the avatar. Supplying this without [profileImageUrl] still shows
  /// the avatar, using the fallback person icon.
  final VoidCallback? onProfileTap;

  /// Extra trailing widgets, placed left of the avatar.
  final List<Widget> actions;

  /// Uses the shorter 70px variant from the mock-up.
  final bool compact;

  /// Defaults to the scaffold cream. Override for a screen that needs contrast.
  final Color? backgroundColor;

  bool get _hasProfile => profileImageUrl != null || onProfileTap != null;

  @override
  Size get preferredSize => Size.fromHeight(
    compact ? AppSizes.appBarHeightCompact : AppSizes.appBarHeight,
  );

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    final bool showBack = showBackButton ?? canPop;

    return Material(
      color: backgroundColor ?? AppColors.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: <Widget>[
                // Leading -------------------------------------------------
                if (showBack)
                  _BarIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: AppSizes.minTapTarget),

                // Title ---------------------------------------------------
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleLarge,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall,
                        ),
                    ],
                  ),
                ),

                // Trailing ------------------------------------------------
                ...actions,
                if (_hasProfile)
                  _ProfileAvatar(
                    imageUrl: profileImageUrl,
                    onTap: onProfileTap,
                  )
                else if (actions.isEmpty)
                  // Balances the leading slot so the title stays centred.
                  const SizedBox(width: AppSizes.minTapTarget),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Square tap target holding one app-bar icon.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: AppSizes.minTapTarget,
        height: AppSizes.minTapTarget,
        child: Icon(
          icon,
          size: AppSizes.appBarIconSize,
          color: AppColors.textPrimary,
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Circular avatar on the right of the app bar.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.imageUrl, required this.onTap});

  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: AppSizes.minTapTarget,
          height: AppSizes.minTapTarget,
          child: Center(
            child: Container(
              width: AppSizes.avatarSm,
              height: AppSizes.avatarSm,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? const Icon(
                      Icons.person_outline,
                      size: 20,
                      color: AppColors.textSecondary,
                    )
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_outline,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
