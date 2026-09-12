import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../view_models/dashboard_view_model.dart' show MapSelectionHandoff;
import '../../view_models/landmark_place_detail_view_model.dart';
import '../../view_models/report_place_view_model.dart';
import '../common_widgets/app_image.dart';
import '../common_widgets/app_tag_chip.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import '../common_widgets/food_image_fallback.dart';
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

  /// Opens the full-screen report page (shared by restaurants and landmarks).
  /// The place rides [ReportPlaceHandoff] - routes pass no arguments (see
  /// `AppNavigator` / the codebase's handoff convention). If the report froze
  /// or removed the landmark, the page pops `true` and this screen leaves too
  /// so the now-hidden pin is no longer shown.
  Future<void> _openReport(SubmittedLandmark landmark) async {
    ReportPlaceHandoff()
      ..pendingKind = ReportPlaceKind.landmark
      ..pendingPlaceId = landmark.id
      ..pendingName = landmark.name;
    final bool? hidPlace = await AppNavigator.push<bool>(AppRoutes.reportPlace);
    if (!mounted || hidPlace != true) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
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
                  return _LandmarkDetails(
                    landmark: landmark,
                    distanceMetres: viewModel.landmarkDistanceMetres,
                    onReport: () => _openReport(landmark),
                  );
                },
          ),
        ),
      ),
    );
  }
}

/// The ready-state content - presented EXACTLY like the catalogue's
/// `RestaurantDetailView` (same frame, header, information card and section
/// headings): the landmark's header (photo, name, category, location), one
/// information card holding its contact details and opening hours, and its
/// dishes. Two deliberate differences: no rating/reviews (tourists do not
/// rate submitted landmarks - the header row shows the DISTANCE instead),
/// and the header keeps its "Open Google Maps" link, because getting to a
/// submitted pin is the main reason to open this page.
class _LandmarkDetails extends StatelessWidget {
  const _LandmarkDetails({
    required this.landmark,
    required this.distanceMetres,
    required this.onReport,
  });

  final SubmittedLandmark landmark;

  /// Straight-line metres from the tourist, or null when unknown - see
  /// `LandmarkPlaceDetailViewModel.landmarkDistanceMetres`.
  final double? distanceMetres;

  /// Opens the report sheet - wired in `_LandmarkPlaceDetailViewState` so it
  /// can reach the ViewModel's `submitReport` and show the confirmation.
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Same frame as the catalogue's `RestaurantDetailView` - the two place
      // pages are the same kind of screen and must read the same.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: <Widget>[
        _LandmarkHeader(landmark: landmark, distanceMetres: distanceMetres),
        const SizedBox(height: AppSpacing.xl),
        _LandmarkInformationSection(landmark: landmark),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Dishes',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        const SizedBox(height: AppSpacing.md),
        if (landmark.items.isEmpty)
          Text(
            'No dishes recorded for this landmark yet.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          )
        else
          for (final LandmarkItem item in landmark.items) ...<Widget>[
            // Display-only, exactly like the restaurant page's menu rows -
            // there is no way into a dish's details from here anymore.
            _DishCard(item: item),
            const SizedBox(height: AppSpacing.sm),
          ],
        const SizedBox(height: AppSpacing.lg),
        // Report affordance - mirrors the catalogue restaurant detail's
        // "Report Restaurant" button: lets a tourist flag an incorrect
        // submitted-landmark pin. UI-only for now, like the restaurant one.
        OutlinedButton.icon(
          onPressed: onReport,
          icon: const Icon(Icons.flag_outlined, color: AppColors.error),
          label: const Text('Report Landmark'),
        ),
      ],
    );
  }
}

class _LandmarkHeader extends StatelessWidget {
  const _LandmarkHeader({required this.landmark, required this.distanceMetres});

  final SubmittedLandmark landmark;

  /// Straight-line metres from the tourist - see [_MetaRow.distanceMetres].
  final double? distanceMetres;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Photo(landmark: landmark),
        const SizedBox(height: AppSpacing.lg),
        Text(
          landmark.name.isEmpty ? 'Unnamed landmark' : landmark.name,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        _MetaRow(landmark: landmark, distanceMetres: distanceMetres),
        const SizedBox(height: AppSpacing.md),
        if (landmark.category.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              AppTagChip(label: landmark.category, style: AppTagStyle.category),
            ],
          )
        else
          Text(
            'Landmark submitted by a tourist',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        if (landmark.status == LandmarkStatus.frozen) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This landmark is temporarily hidden after being reported.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// The landmark's photo - the SAME 2:1 rounded frame the catalogue's
/// restaurant header uses, so the two place pages are not visually different
/// kinds of screen. `cover` crops a tall stall photo to fill that frame; the
/// trade-off is deliberate (uniform presentation over showing every edge of
/// the submitted photo). A missing DB value ("No photo") is shown
/// differently from a photo the app tried and failed to load ("Couldn't
/// load" - usually the storage bucket not being public).
class _Photo extends StatelessWidget {
  const _Photo({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    final String? url = landmark.imageUrl;
    if (url == null || url.isEmpty) {
      return AspectRatio(aspectRatio: 2, child: _placeholder('No photo'));
    }
    return AspectRatio(
      aspectRatio: 2,
      child: AppImage(
        source: url,
        borderRadius: AppRadius.cardRadius,
        semanticLabel: landmark.name,
        fallback: _placeholder('Couldn’t load'),
      ),
    );
  }

  Widget _placeholder(String label) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
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

/// Distance + Google Maps line under the header, laid out like the
/// restaurant detail's row: the "Open Google Maps" link sits on the LEFT,
/// and the location icon + how far away the landmark is on the RIGHT - the
/// same side and icon+text style the restaurant uses for its distance. No
/// rating/reviews (a tourist cannot rate a submitted landmark) and no
/// report count (moderation data the tourist does not need to see).
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.landmark, required this.distanceMetres});

  final SubmittedLandmark landmark;

  /// Straight-line metres from the tourist, or null when there is no fix or
  /// the landmark has no coordinates - see
  /// `LandmarkPlaceDetailViewModel.landmarkDistanceMetres`.
  final double? distanceMetres;

  @override
  Widget build(BuildContext context) {
    final double? lat = landmark.latitude;
    final double? lon = landmark.longitude;
    final bool hasLocation = lat != null && lon != null;
    return Row(
      children: <Widget>[
        if (hasLocation)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => _openInGoogleMaps(context, lat, lon),
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
        const Spacer(),
        const Icon(Icons.location_on_outlined),
        const SizedBox(width: AppSpacing.xs),
        Text(_distanceLabel(distanceMetres)),
      ],
    );
  }

  /// Same wording and format as the restaurant header's distance label
  /// (`RestaurantDetailHeader._distanceLabel`), so the two place pages read
  /// identically: "850 m", "1.2 km", or "Distance unavailable".
  String _distanceLabel(double? metres) {
    if (metres == null) return 'Distance unavailable';
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}

/// Opens Google Maps centred on ([lat], [lon]) via the universal web link
/// (`google.com/maps/search`), which opens the Google Maps app if it's
/// installed, or falls back to a browser otherwise - the same behaviour on
/// Android and iOS without needing platform-specific URI schemes.
Future<void> _openInGoogleMaps(
  BuildContext context,
  double lat,
  double lon,
) async {
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

/// The landmark's contact details and opening hours in ONE card, matching
/// the catalogue restaurant detail's "Restaurant Information" card (white
/// surface, bordered, section headings in accent brown) - the two place
/// pages must present their facts the same way. Absent fields degrade to
/// the same "unavailable" wording the restaurant card uses rather than
/// vanishing.
class _LandmarkInformationSection extends StatelessWidget {
  const _LandmarkInformationSection({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Landmark Information', style: _sectionStyle(context)),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
            icon: Icons.location_on_outlined,
            label: landmark.address.isEmpty
                ? 'Address unavailable'
                : landmark.address,
          ),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
            icon: Icons.phone_outlined,
            label: landmark.phone.isEmpty
                ? 'Phone unavailable'
                : landmark.phone,
          ),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
            icon: Icons.language_outlined,
            label: landmark.website.isEmpty
                ? 'Website unavailable'
                : landmark.website,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Opening Hours', style: _sectionStyle(context)),
          const SizedBox(height: AppSpacing.md),
          _OpeningHoursList(hours: landmark.openingHours),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown);
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: AppColors.accentBrown),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label)),
      ],
    );
  }
}

/// The landmark's recorded hours, one bare row per day (day left, time
/// right) exactly like the restaurant detail's opening-hours table - the
/// enclosing [_LandmarkInformationSection] card is what frames them now.
/// Honours all three [DayStatus] states (matching the add-landmark form's
/// wording): an Open row shows its time range, a day recorded as Unknown
/// reads "Hours not known" - never "Closed" - and only a day the submitter
/// confirmed closed reads "Closed". The app does not tell a tourist a place
/// is shut when it does not know (the same rule the map's "Hours unknown"
/// label follows).
class _OpeningHoursList extends StatelessWidget {
  const _OpeningHoursList({required this.hours});

  final List<OpeningHour> hours;

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) {
      return Text(
        'Opening hours are not available yet.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final OpeningHour hour in hours)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(_dayName(hour.day))),
                Text(_hoursLabel(hour)),
              ],
            ),
          ),
      ],
    );
  }

  String _hoursLabel(OpeningHour hour) => switch (hour.status) {
    DayStatus.open when hour.opensAt != null && hour.closesAt != null =>
      '${_clock(hour.opensAt!)} - ${_clock(hour.closesAt!)}',
    DayStatus.unknown => 'Hours not known',
    _ => 'Closed',
  };
}

/// One dish attached to the landmark - presented exactly as the catalogue
/// restaurant detail's menu rows are (square photo, dish name, category,
/// price in rust) and, like those rows, NOT tappable: the restaurant page
/// offers no way into a dish's details either, so the two place pages
/// present their dishes identically. The NAME shown is the VARIANT the
/// tourist actually photographed / typed ("Cendol Jagung") when one was
/// recorded - the landmark lists what was captured - falling back to the
/// dictionary dish (the `local_food` row it links to). Origin, cooking
/// style, cultural background, meal type and the description are not shown
/// here.
class _DishCard extends StatelessWidget {
  const _DishCard({required this.item});

  final LandmarkItem item;

  @override
  Widget build(BuildContext context) {
    final String? price = landmarkItemPriceLabel(item);
    final String name = item.displayName.isEmpty
        ? 'Unnamed dish'
        : item.displayName;
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: AppSizes.pairingImage,
            child: AppImage(
              source: item.imageUrl,
              borderRadius: AppRadius.cardRadius,
              semanticLabel: name,
              fallback: const FoodImageFallback(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: Theme.of(context).textTheme.titleSmall),
                if (item.foodCategory.isNotEmpty)
                  Text(
                    item.foodCategory,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (price != null)
            Text(
              price,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: AppColors.accentRust),
            ),
        ],
      ),
    );
  }
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

/// Minutes since midnight -> "1:30 AM" - the same clock format the
/// restaurant detail's opening-hours table uses, so the two place pages do
/// not disagree about how a time reads.
String _clock(int minutes) {
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  final String period = h >= 12 ? 'PM' : 'AM';
  final int displayHour = h % 12 == 0 ? 12 : h % 12;
  return '$displayHour:${m.toString().padLeft(2, '0')} $period';
}
