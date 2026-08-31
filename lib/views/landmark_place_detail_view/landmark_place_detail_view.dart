import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../view_models/dashboard_view_model.dart' show MapSelectionHandoff;
import '../../view_models/landmark_place_detail_view_model.dart';
import '../common_widgets/app_image.dart';
import '../common_widgets/app_tag_chip.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import '../common_widgets/landmark_item_formatting.dart';

/// Full details of a tourist-submitted landmark (A11-4 "View Landmark"),
/// reached from the dashboard map's pin sheet. Shows the landmark's photo,
/// name, category and location, its opening hours, and every dish attached
/// to it.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class LandmarkPlaceDetailView extends StatefulWidget {
  const LandmarkPlaceDetailView({super.key});

  @override
  State<LandmarkPlaceDetailView> createState() =>
      _LandmarkPlaceDetailViewState();
}

class _LandmarkPlaceDetailViewState extends State<LandmarkPlaceDetailView> {
  late final LandmarkPlaceDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LandmarkPlaceDetailViewModel();

    // Pick up the tapped landmark's id handed over by the dashboard map's
    // "View Landmark" button - BEFORE onInit(). Same hand-off pattern as
    // AddLandmarkView itself.
    final int? landmarkId = MapSelectionHandoff().takeLandmarkId();
    if (landmarkId != null) _viewModel.setLandmarkId(landmarkId);
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkPlaceDetailViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Landmark'),
        body: SafeArea(
          child: Consumer<LandmarkPlaceDetailViewModel>(
            builder:
                (
                  BuildContext context,
                  LandmarkPlaceDetailViewModel viewModel,
                  Widget? _,
                ) {
                  if (viewModel.isBusy) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (viewModel.hasError) {
                    return AsyncMessage(
                      icon: Icons.error_outline,
                      title: "Couldn't load this landmark",
                      message: viewModel.errorMessage,
                      actionLabel: 'Retry',
                      onAction: viewModel.load,
                    );
                  }
                  final SubmittedLandmark? landmark = viewModel.landmark;
                  if (landmark == null) {
                    return const AsyncMessage(
                      icon: Icons.location_off_outlined,
                      title: 'No landmark to show',
                    );
                  }
                  return _LandmarkDetails(landmark: landmark);
                },
          ),
        ),
      ),
    );
  }
}

/// The ready-state content - the landmark's header (photo, name, category,
/// location), its opening hours, and its dishes.
class _LandmarkDetails extends StatelessWidget {
  const _LandmarkDetails({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.screenPadding,
      children: <Widget>[
        _LandmarkHeader(landmark: landmark),
        if (landmark.openingHours.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const Text('Opening Hours', style: AppTextStyles.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _OpeningHoursList(hours: landmark.openingHours),
        ],
        const SizedBox(height: AppSpacing.lg),
        const Text('Dishes', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (landmark.items.isEmpty)
          Text(
            'No dishes recorded for this landmark yet.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          )
        else
          for (final LandmarkItem item in landmark.items) ...<Widget>[
            _DishCard(
              item: item,
              // Every dish navigates now, resolved to a catalogue entry or
              // not - LandmarkItemDetailView reads straight off the
              // LandmarkItem already in hand (via LandmarkItemHandoff), no
              // network fetch, so there's no reason to withhold it just
              // because a dish never matched the catalogue. (This used to
              // route to the catalogue's FoodDetailView by localFoodId
              // instead - that meant an unresolved dish had nowhere to go,
              // and a resolved one paid for a redundant re-fetch of data
              // this screen already loaded.)
              onTap: () {
                LandmarkItemHandoff().pendingItem = item;
                Navigator.pushNamed(context, AppRoutes.landmarkItemDetail);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _LandmarkHeader extends StatelessWidget {
  const _LandmarkHeader({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Photo(landmark: landmark),
        const SizedBox(height: AppSpacing.md),
        Text(
          landmark.name.isEmpty ? 'Unnamed landmark' : landmark.name,
          style: AppTextStyles.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (landmark.category.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              landmark.category,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Text(
            'Landmark submitted by a tourist',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        _MetaLine(landmark: landmark),
        if (landmark.status == LandmarkStatus.frozen) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This landmark is temporarily hidden after being reported.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// The landmark's photo, sized to match its own aspect ratio -
/// [SubmittedLandmark.imageCategory] tells us whether it's a wide/short
/// signboard photo or a tall stall photo, so the frame it's shown in can
/// actually fit it instead of forcing both shapes into one box. A missing DB
/// value ("No photo") is shown differently from a photo the app tried and
/// failed to load ("Couldn't load" - usually the storage bucket not being
/// public).
class _Photo extends StatelessWidget {
  const _Photo({required this.landmark});

  final SubmittedLandmark landmark;

  double get _height => switch (landmark.imageCategory) {
    'stall' => AppSizes.landmarkPhotoHeightTall,
    'signboard' => AppSizes.landmarkPhotoHeightWide,
    _ => AppSizes.landmarkPhotoHeightDefault,
  };

  @override
  Widget build(BuildContext context) {
    final String? url = landmark.imageUrl;
    if (url == null || url.isEmpty) {
      return _placeholder('No photo');
    }
    return Container(
      height: _height,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: AppRadius.cardRadius,
      ),
      child: AppImage(
        source: url,
        // `contain`, not the default `cover` - the whole point of sizing the
        // frame by imageCategory is that nothing should ever need to be
        // cropped to fit. `contain` guarantees the full photo is always
        // visible, even if the frame and the photo's exact ratio don't
        // match perfectly.
        fit: BoxFit.contain,
        borderRadius: AppRadius.cardRadius,
        semanticLabel: landmark.name,
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
      borderRadius: AppRadius.cardRadius,
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.location_on, size: 40, color: AppColors.textSecondary),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    ),
  );
}

/// Location and reported-count line under the header - each field degrades
/// on its own (no location is simply absent). The location has two separate
/// affordances: tap-to-copy (unchanged), and a "near me"/navigation icon
/// that opens Google Maps centred on these exact coordinates - a tourist
/// looking at this page almost certainly wants to actually get there, not
/// just read the numbers.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    final double? lat = landmark.latitude;
    final double? lon = landmark.longitude;
    final String? location = (lat != null && lon != null)
        ? '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}'
        : null;
    final String? reports = landmark.reportedCount > 0
        ? 'Reported ${landmark.reportedCount}×'
        : null;
    if (location == null && reports == null) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        if (location != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: location));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coordinates copied')),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.cardBorder),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.place_outlined,
                        size: AppSizes.iconSmall,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        location,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(
                        Icons.copy_outlined,
                        size: AppSizes.inlineNoticeIconSize,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => _openInGoogleMaps(context, lat!, lon!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.near_me,
                        size: AppSizes.inlineNoticeIconSize,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Open Google Maps',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (reports != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.flag_outlined,
                size: 14,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(reports, style: AppTextStyles.bodySmall),
            ],
          ),
      ],
    );
  }
}

/// Opens Google Maps centred on ([lat], [lon]) via the universal web link
/// (`google.com/maps/search`), which opens the Google Maps app if it's
/// installed, or falls back to a browser otherwise - the same behaviour on
/// Android and iOS without needing platform-specific URI schemes.
Future<void> _openInGoogleMaps(BuildContext context, double lat, double lon) async {
  final Uri uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
  );
  final bool launched = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open Google Maps.')),
    );
  }
}

/// The landmark's recorded hours, one line per row. Days with no recorded
/// times read "Closed" (the wire format has no separate "unknown" row).
class _OpeningHoursList extends StatelessWidget {
  const _OpeningHoursList({required this.hours});

  final List<OpeningHour> hours;

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> rows = <(String, String)>[
      for (final OpeningHour hour in hours)
        (
          _dayName(hour.day),
          hour.status == DayStatus.open &&
                  hour.opensAt != null &&
                  hour.closesAt != null
              ? '${_clock(hour.opensAt!)} - ${_clock(hour.closesAt!)}'
              : 'Closed',
        ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        children: <Widget>[
          for (final (String day, String time) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(day, style: AppTextStyles.bodyMedium)),
                  Text(
                    time,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One dish attached to the landmark - its photo, name, price, and its meal
/// type/category as colour-coded pills - matching `LocalFoodCard`'s exact
/// layout (the catalogue's own list card), so a dish here doesn't look like
/// a visually different kind of thing from a catalogue food elsewhere in
/// the app. Variant, origin, cooking style and cultural background are
/// deliberately NOT shown here - that's what tapping through to
/// `LandmarkItemDetailView` is for; a list card showing everything a detail
/// page also shows left nothing for the detail page to add, and read as a
/// wall of small grey text. Always tappable - see the call site's doc for
/// why every dish now has somewhere to go.
class _DishCard extends StatelessWidget {
  const _DishCard({required this.item, required this.onTap});

  final LandmarkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? price = landmarkItemPriceLabel(item);
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.cardElevation,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox.square(
                dimension: AppSizes.foodCardImage,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.cardBorder),
                    borderRadius: AppRadius.cardRadius,
                  ),
                  child: AppImage(
                    source: item.imageUrl,
                    semanticLabel: item.dish,
                    borderRadius: AppRadius.cardRadius,
                    fallback: const _DishImageUnavailable(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.dish.isEmpty ? 'Unnamed dish' : item.dish,
                            style: AppTextStyles.titleSmall,
                          ),
                        ),
                        if (price != null) ...<Widget>[
                          Text(
                            price,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.accentRust,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        if (item.mealType.isNotEmpty)
                          AppTagChip(label: item.mealType, style: AppTagStyle.meal),
                        if (item.foodCategory.isNotEmpty)
                          AppTagChip(
                            label: item.foodCategory,
                            style: AppTagStyle.category,
                          ),
                      ],
                    ),
                    if (item.description.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DishImageUnavailable extends StatelessWidget {
  const _DishImageUnavailable();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Image unavailable',
    image: true,
    child: ColoredBox(
      color: AppColors.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.restaurant_menu, color: AppColors.accentBrown),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No image',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.accentBrownMuted,
            ),
          ),
        ],
      ),
    ),
  );
}

String _dayName(Weekday day) => switch (day) {
  Weekday.monday => 'Monday',
  Weekday.tuesday => 'Tuesday',
  Weekday.wednesday => 'Wednesday',
  Weekday.thursday => 'Thursday',
  Weekday.friday => 'Friday',
  Weekday.saturday => 'Saturday',
  Weekday.sunday => 'Sunday',
};

/// Minutes since midnight -> "HH:MM".
String _clock(int minutes) {
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
