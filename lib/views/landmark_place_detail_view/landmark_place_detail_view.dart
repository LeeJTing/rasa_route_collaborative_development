import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routing/app_navigator.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import '../../view_models/dashboard_view_model.dart' show MapSelectionHandoff;
import '../../view_models/landmark_place_detail_view_model.dart';
import '../../view_models/report_place_view_model.dart';
import '../common_widgets/app_image.dart';
import '../common_widgets/app_tag_chip.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import '../common_widgets/food_image_fallback.dart';
import '../common_widgets/landmark_item_formatting.dart';
import '../common_widgets/place_menu_section.dart';
import 'widgets/landmark_information_section.dart';

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
  /// `AppNavigator` / the codebase's handoff convention). Its coordinates ride
  /// along too: the address report's map opens on the spot the app currently
  /// places this landmark. If the report froze or removed the landmark, the
  /// page pops `true` and this screen leaves too so the now-hidden pin is no
  /// longer shown.
  Future<void> _openReport(SubmittedLandmark landmark) async {
    final double? latitude = landmark.latitude;
    final double? longitude = landmark.longitude;
    ReportPlaceHandoff()
      ..pendingKind = ReportPlaceKind.landmark
      ..pendingPlaceId = landmark.id
      ..pendingName = landmark.name
      ..pendingLocation = latitude == null || longitude == null
          ? TouristLocation.unknown
          : TouristLocation(latitude: latitude, longitude: longitude);
    final bool? hidPlace = await AppNavigator.push<bool>(AppRoutes.reportPlace);
    if (!mounted || hidPlace != true) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkPlaceDetailViewModel>.value(
      value: _viewModel,
      // The bar lives INSIDE the consumer so it can carry the landmark's own
      // name, exactly like `RestaurantDetailView` does - a bare "Landmark"
      // title told the tourist nothing about which place they had opened.
      // The placeholder shows until the fetch lands.
      child: Consumer<LandmarkPlaceDetailViewModel>(
        builder:
            (
              BuildContext context,
              LandmarkPlaceDetailViewModel viewModel,
              Widget? _,
            ) {
              final SubmittedLandmark? landmark = viewModel.landmark;
              return Scaffold(
                appBar: AppTopBar(
                  title: landmark == null || landmark.name.trim().isEmpty
                      ? 'Landmark Details'
                      : landmark.name,
                ),
                body: SafeArea(child: _body(viewModel, landmark)),
                // Pinned to the bottom of the screen, exactly like the
                // catalogue restaurant page's "Report Restaurant" bar - the
                // tourist must not have to scroll past every dish to find the
                // way to flag a wrong pin. Only once there is something to
                // report.
                bottomNavigationBar: landmark == null
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: OutlinedButton.icon(
                            onPressed: () => _openReport(landmark),
                            icon: const Icon(
                              Icons.flag_outlined,
                              color: AppColors.error,
                            ),
                            label: const Text('Report Landmark'),
                          ),
                        ),
                      ),
              );
            },
      ),
    );
  }

  /// The body's states: loading, failed, nothing-to-show, or the details.
  /// (The app bar above shows the name as soon as [landmark] exists.)
  Widget _body(
    LandmarkPlaceDetailViewModel viewModel,
    SubmittedLandmark? landmark,
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
    if (landmark == null) {
      return const AsyncMessage(
        icon: Icons.location_off_outlined,
        title: 'No landmark to show',
      );
    }
    return _LandmarkDetails(
      landmark: landmark,
      distanceMetres: viewModel.landmarkDistanceMetres,
    );
  }
}

/// The ready-state content - presented EXACTLY like the catalogue's
/// `RestaurantDetailView` (same frame, header, information card and section
/// headings): the landmark's header (photo, name, category, location), one
/// information card holding its contact details and opening hours, and its
/// dishes. Two deliberate differences: no rating/reviews (tourists do not
/// rate submitted landmarks - the header row shows the DISTANCE instead),
/// and no separate "Open Google Maps" link of its own in the header: the
/// address row in the information card IS the way to the map (it falls back
/// to the coordinates), exactly like the restaurant page (user report,
/// 2026-09-13).
class _LandmarkDetails extends StatelessWidget {
  const _LandmarkDetails({
    required this.landmark,
    required this.distanceMetres,
  });

  final SubmittedLandmark landmark;

  /// Straight-line metres from the tourist, or null when unknown - see
  /// `LandmarkPlaceDetailViewModel.landmarkDistanceMetres`.
  final double? distanceMetres;

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
        LandmarkInformationSection(
          landmark: landmark,
          // Same actions the restaurant page gives the same rows: the address
          // opens Google Maps (at the landmark's coordinates - that is what a
          // submitted pin IS - else searched by its address text), the phone
          // the dialler, the website the browser.
          onAddressTap: () => _openMapsQuery(context, _mapsQueryFor(landmark)),
          onPhoneTap: () => _openPhone(context, landmark.phone),
          onWebsiteTap: () => _openWebsite(context, landmark.website),
        ),
        const SizedBox(height: AppSpacing.xl),
        // The SAME section the catalogue's restaurant page shows, wording and
        // collapse included - only the rows differ, because they read a
        // different model (user request: "the landmark should display the
        // same way").
        PlaceMenuSection(
          itemCount: landmark.items.length,
          emptyMessage: 'No dishes recorded for this landmark yet.',
          children: <Widget>[
            for (final LandmarkItem item in landmark.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _DishCard(item: item),
              ),
          ],
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
    // The category MOST of its dishes carry (`displayCategory`), worded the
    // way the catalogue's own places read theirs ("Chinese restaurant"), and
    // shown as the restaurant page shows it: one chip under the name. No
    // fallback text when there is genuinely nothing - "Landmark submitted by
    // a tourist" said nothing about the place (user report, 2026-09-13).
    final String category = landmark.displayCategoryLabel;
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
        _MetaRow(distanceMetres: distanceMetres),
        const SizedBox(height: AppSpacing.md),
        if (category.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              AppTagChip(label: category, style: AppTagStyle.category),
            ],
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

/// The distance line under the header, left-aligned with the name and the
/// category chip below it (same icon + text style the restaurant page uses
/// for its own distance). No rating/reviews (a tourist cannot rate a
/// submitted landmark) and no report count (moderation data the tourist
/// does not need to see).
///
/// It carries no "Open Google Maps" link of its own any more - the address
/// row in the information card below opens the map (at the landmark's
/// coordinates, or searched by its address), so a second link to the same
/// destination only crowded the header. While that link existed it filled
/// the left half of this row and the distance sat on the right; with the link
/// gone the right-aligned distance left an empty band above the chip, so the
/// distance moved in line with the text above and below it (user report:
/// "the Category have a gap with whatever is above it").
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.distanceMetres});

  /// Straight-line metres from the tourist, or null when there is no fix or
  /// the landmark has no coordinates - see
  /// `LandmarkPlaceDetailViewModel.landmarkDistanceMetres`.
  final double? distanceMetres;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const Icon(Icons.location_on_outlined),
      const SizedBox(width: AppSpacing.xs),
      Text(_distanceLabel(distanceMetres)),
    ],
  );

  /// Same wording and format as the restaurant header's distance label
  /// (`RestaurantDetailHeader._distanceLabel`), so the two place pages read
  /// identically: "850 m", "1.2 km", or "Distance unavailable".
  String _distanceLabel(double? metres) {
    if (metres == null) return 'Distance unavailable';
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}

/// The Google Maps query for a landmark: its coordinates when known (that is
/// what a submitted pin IS), its address text otherwise.
String _mapsQueryFor(SubmittedLandmark landmark) {
  final double? latitude = landmark.latitude;
  final double? longitude = landmark.longitude;
  if (latitude != null && longitude != null) return '$latitude,$longitude';
  return landmark.address.trim();
}

/// Opens a Google Maps search ([query] = "lat,lon" or an address) via the
/// universal web link (`google.com/maps/search`), which opens the Google Maps
/// app if it's installed, or falls back to a browser otherwise - the same
/// behaviour on Android and iOS without needing platform-specific URI
/// schemes.
Future<void> _openMapsQuery(BuildContext context, String query) => _launchUri(
  context,
  Uri.https('www.google.com', '/maps/search/', <String, String>{
    'api': '1',
    'query': query,
  }),
  'Unable to open Google Maps.',
);

/// Opens the dialler on [phone] (a `tel:` link).
Future<void> _openPhone(BuildContext context, String phone) => _launchUri(
  context,
  Uri(scheme: 'tel', path: phone.trim()),
  'Unable to open the phone app.',
);

/// Opens a website link, adding the scheme when the stored value has none -
/// the same normalisation the restaurant page applies.
Future<void> _openWebsite(BuildContext context, String rawWebsite) {
  final String value = rawWebsite.trim();
  final Uri? parsed = Uri.tryParse(value);
  final Uri? uri =
      parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')
      ? parsed
      : Uri.tryParse('https://$value');
  if (uri == null || uri.host.isEmpty) {
    _showLaunchFailure(context, 'This landmark website is invalid.');
    return Future<void>.value();
  }
  return _launchUri(context, uri, 'Unable to open the website.');
}

/// One launcher for every external link on this page - the "could not open"
/// snackbar lives here, so the address, phone and website rows all fail the
/// same way.
Future<void> _launchUri(
  BuildContext context,
  Uri uri,
  String failureMessage,
) async {
  try {
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      _showLaunchFailure(context, failureMessage);
    }
  } catch (_) {
    if (context.mounted) _showLaunchFailure(context, failureMessage);
  }
}

void _showLaunchFailure(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// One dish attached to the landmark - the SAME row the catalogue restaurant
/// detail's menu shows (square photo, dish name, a two-line description when
/// one was recorded, the food category, price in rust) and, like those rows,
/// NOT tappable: the restaurant page offers no way into a dish's details
/// either, so the two place pages present their dishes identically. The NAME
/// shown is the VARIANT the tourist actually photographed / typed ("Cendol
/// Jagung") when one was recorded - the landmark lists what was captured -
/// falling back to the dictionary dish (the `local_food` row it links to).
/// Origin, cooking style, cultural background and meal type are not shown
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
    final String description = item.description.trim();
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
                if (description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
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
