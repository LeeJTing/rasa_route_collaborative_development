import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../view_models/landmark_item_detail_view_model.dart';
import '../../view_models/landmark_place_detail_view_model.dart'
    show LandmarkItemHandoff;
import '../common_widgets/app_image.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import '../common_widgets/landmark_item_formatting.dart';
import '../common_widgets/food_section_card.dart';

/// Full details of one dish attached to a tourist-submitted landmark,
/// reached by tapping a dish card on `LandmarkPlaceDetailView`. Reads
/// straight off the `LandmarkItem` already in hand - no network fetch,
/// since the landmark screen already loaded everything this dish carries.
/// Deliberately NOT the same screen as the catalogue's `FoodDetailView`:
/// that screen fetches a `LocalFood` by id from the catalogue, which would
/// mean re-fetching data this screen already has, and would show nothing at
/// all for a dish that never resolved to a catalogue entry.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class LandmarkItemDetailView extends StatefulWidget {
  const LandmarkItemDetailView({super.key});

  @override
  State<LandmarkItemDetailView> createState() => _LandmarkItemDetailViewState();
}

class _LandmarkItemDetailViewState extends State<LandmarkItemDetailView> {
  late final LandmarkItemDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LandmarkItemDetailViewModel();

    final LandmarkItem? item = LandmarkItemHandoff().takeItem();
    if (item != null) _viewModel.setItem(item);
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkItemDetailViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Dish Details'),
        body: SafeArea(
          child: Consumer<LandmarkItemDetailViewModel>(
            builder:
                (
                  BuildContext context,
                  LandmarkItemDetailViewModel viewModel,
                  Widget? _,
                ) {
                  final LandmarkItem? item = viewModel.item;
                  if (item == null) {
                    return const AsyncMessage(
                      icon: Icons.restaurant_outlined,
                      title: 'No dish to show',
                    );
                  }
                  return _ItemDetails(item: item);
                },
          ),
        ),
      ),
    );
  }
}

class _ItemDetails extends StatelessWidget {
  const _ItemDetails({required this.item});

  final LandmarkItem item;

  @override
  Widget build(BuildContext context) {
    final String? price = landmarkItemPriceLabel(item);
    return ListView(
      padding: AppSpacing.screenPadding,
      children: <Widget>[
        _Photo(item: item),
        const SizedBox(height: AppSpacing.md),
        Text(
          item.displayName.isEmpty ? 'Unnamed dish' : item.displayName,
          style: AppTextStyles.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            if (price != null)
              _Pill(
                text: price,
                background: AppColors.primaryContainer,
                icon: Icons.payments_outlined,
              ),
            if (item.foodCategory.isNotEmpty)
              _Pill(
                text: item.foodCategory,
                background: AppColors.secondaryContainer,
                icon: Icons.category_outlined,
              ),
            if (item.mealType.isNotEmpty)
              _Pill(
                text: item.mealType,
                background: AppColors.secondaryContainer,
                icon: Icons.schedule,
              ),
          ],
        ),
        if (item.origin.isNotEmpty || item.cookingStyle.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          _IconSection(
            icon: Icons.public,
            label: 'Origin & Cooking Style',
            body: <String>[
              if (item.origin.isNotEmpty) item.origin,
              if (item.cookingStyle.isNotEmpty) item.cookingStyle,
            ].join(' · '),
          ),
        ],
        if (item.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          _IconSection(
            icon: Icons.description_outlined,
            label: 'Description',
            body: item.description,
          ),
        ],
        if (item.culturalBackground.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          _IconSection(
            icon: Icons.history_edu_outlined,
            label: 'Cultural Background',
            body: item.culturalBackground,
          ),
        ],
      ],
    );
  }
}

/// The dish's own photo (`LandmarkItem.imageUrl`) - not shown at all on the
/// compact `_DishCard`, so this is the first place a tourist sees it.
/// Larger corner radius than a typical card ([AppRadius.lg], not
/// [AppRadius.cardRadius]) so it reads as the page's hero element rather
/// than a bordered thumbnail.
class _Photo extends StatelessWidget {
  const _Photo({required this.item});

  final LandmarkItem item;

  static const double _height = 220;

  @override
  Widget build(BuildContext context) {
    final String? url = item.imageUrl;
    if (url == null || url.isEmpty) {
      return _placeholder('No photo');
    }
    return Container(
      height: _height,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
      ),
      child: AppImage(
        source: url,
        fit: BoxFit.contain,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
        semanticLabel: item.displayName,
        fallback: _placeholder('Couldn’t load'),
      ),
    );
  }

  Widget _placeholder(String label) => Container(
    height: _height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      border: Border.all(color: AppColors.cardBorder),
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.restaurant_outlined,
          size: 40,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    ),
  );
}

/// A small coloured pill with an optional leading icon - price, category,
/// meal type, and the "in the catalogue" status all use this same shape,
/// so nothing on the page mixes plain text with pills for the same kind of
/// at-a-glance information.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.background, this.icon});

  final String text;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: AppSizes.inlineNoticeIconSize,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled block of text (Origin & Cooking Style / Description /
/// Cultural Background), wrapped in the same `FoodSectionCard` treatment
/// `FoodDetailView` already uses for this exact kind of content - warm
/// border, `accentBrown` heading - rather than a bespoke, unbordered
/// section that would be the only place in the app styled that way. The
/// icon sits beside the label, since `FoodSectionCard`'s own `title` is
/// plain text with no room for one.
class _IconSection extends StatelessWidget {
  const _IconSection({
    required this.icon,
    required this.label,
    required this.body,
  });

  final IconData icon;
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return FoodSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                size: AppSizes.iconSmall,
                color: AppColors.accentBrown,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTextStyles.titleSmall.copyWith(
                  color: AppColors.accentBrown,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}
