import 'dart:async';

import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/address_suggestion.dart';
import '../domain_model/opening_hour.dart';
import '../domain_model/report_category.dart';
import '../domain_model/report_claim.dart';
import '../domain_model/report_outcome.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/report_logic_facade.dart';
import 'current_location_facade.dart';
import 'update_restaurant_facade.dart';

/// ViewModel for the full-screen report page (`ReportPlaceView`), shared by
/// catalogue restaurants and submitted landmarks. The tourist picks a
/// category, enters the correction, and the page submits one claim per
/// specific issue (per corrected day for hours; per item for item reports).
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else;
///   * state goes in private fields with read-only getters.
class ReportPlaceViewModel extends BaseViewModel
    implements CurrentLocationListener {
  ReportPlaceViewModel();

  @protected
  ReportLogicFacade createReportLogic() => ReportLogicFacade();

  late final ReportLogicFacade reportLogic = createReportLogic();

  /// Inbound: `LocationMonitor` publishes here. The report page needs the
  /// tourist's own position for ONE thing - the silent on-site check that
  /// decides whether their claim counts (see `_isOnsite`). Nothing about
  /// it is shown.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  /// The tourist's latest fix, unknown until the first GPS tick arrives.
  TouristLocation _currentLocation = TouristLocation.unknown;

  /// Pushed by `LocationMonitor` through [CurrentLocationFacade].
  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _currentLocation = location;
  }

  /// Broadcasts "this tourist changed the map themselves" (a report just hid
  /// the place they were reporting) so every live dashboard silently drops its
  /// caches and re-reads - the hidden pin disappears without a banner.
  final UpdateRestaurantFacade mapRefresh = UpdateRestaurantFacade();

  // --- Place being reported ------------------------------------------------
  ReportPlaceKind? _placeKind;
  int _placeId = 0;
  String _placeName = '';

  ReportPlaceKind? get placeKind => _placeKind;
  String get placeName => _placeName;

  // --- Form state -----------------------------------------------------------
  ReportCategory? _selectedCategory;

  /// Per-day corrections being built for an operating-hours report. Every day
  /// starts Unknown (the form's "I don't know" default); only days the
  /// tourist actively changes to Open/Closed become claims.
  Map<Weekday, List<OpeningHour>> _hours = <Weekday, List<OpeningHour>>{
    for (final Weekday day in Weekday.values)
      day: <OpeningHour>[
        OpeningHour(id: 0, day: day, status: DayStatus.unknown),
      ],
  };

  /// Current menu items (for item categories), loaded on demand.
  List<ReportableMenuItem> _items = const <ReportableMenuItem>[];
  bool _itemsLoading = false;
  String? _itemsError;

  ReportableMenuItem? _selectedItem;

  /// Proposed new price (item-price report), as entered.
  String _priceText = '';

  /// Proposed new address (address report).
  String _addressText = '';

  /// Where the app currently places the reported place (from the handoff) and
  /// where the tourist says it really is. Both unknown when the caller had no
  /// coordinates - the address field then stays a plain text box.
  TouristLocation _placeLocation = TouristLocation.unknown;
  TouristLocation _reportLocation = TouristLocation.unknown;

  /// Whether the field's current text came from the map rather than typing,
  /// and the pin's own composed address behind the "Use the map pin's
  /// address" action.
  bool _addressFromMap = false;
  String? _mapDerivedAddress;
  bool _mapAddressLookupRunning = false;
  bool _mapAddressUnavailable = false;

  /// The address field's live suggestions and their status flags.
  List<AddressSuggestion> _addressSuggestions = const <AddressSuggestion>[];
  bool _addressSearchRunning = false;
  bool _addressSearchUnavailable = false;
  bool _addressSearchEmpty = false;
  Timer? _addressSearchDebounce;
  Timer? _mapAddressDebounce;
  int _addressSearchToken = 0;
  int _addressVersion = 0;

  /// Temporary-closure duration fields.
  String _closureAmountText = '';
  ClosureUnit _closureUnit = ClosureUnit.days;
  String? _priceError;
  String? _addressError;
  String? _closureError;
  String? _hoursError;
  String? _itemError;

  // --- Submit state ---------------------------------------------------------
  bool _isSubmitting = false;
  bool _requiresSignIn = false;
  bool _alreadyReported = false;
  bool _reportFailed = false;
  bool _reportSubmitted = false;
  bool _placeHiddenNow = false;
  String? _formError;
  String _appliedMessage = '';

  ReportCategory? get selectedCategory => _selectedCategory;
  Map<Weekday, List<OpeningHour>> get hours => _hours;
  List<ReportableMenuItem> get items => _items;
  bool get itemsLoading => _itemsLoading;
  String? get itemsError => _itemsError;
  ReportableMenuItem? get selectedItem => _selectedItem;
  String get priceText => _priceText;
  String get addressText => _addressText;
  String get closureAmountText => _closureAmountText;
  ClosureUnit get closureUnit => _closureUnit;
  String? get priceError => _priceError;
  String? get addressError => _addressError;

  /// The address cap the field enforces - the Add-Landmark form's own 150.
  int get addressMaxLength => reportLogic.maxAddressLength;

  /// The amber nudge while the typed address sits in its warn zone (141-149);
  /// the field hides it whenever [addressError] is showing, exactly like the
  /// form's field does.
  String? get addressWarning => reportLogic.addressLengthWarning(_addressText);

  String? get closureError => _closureError;
  String? get hoursError => _hoursError;
  String? get itemError => _itemError;

  bool get isSubmitting => _isSubmitting;
  bool get requiresSignIn => _requiresSignIn;
  bool get alreadyReported => _alreadyReported;
  bool get reportFailed => _reportFailed;
  bool get reportSubmitted => _reportSubmitted;
  bool get placeHiddenNow => _placeHiddenNow;
  String? get formError => _formError;
  String get appliedMessage => _appliedMessage;

  /// Set from `ReportPlaceHandoff` in the View's `initState` before onInit.
  void configure(
    ReportPlaceKind kind,
    int placeId,
    String name,
    TouristLocation location,
  ) {
    _placeKind = kind;
    _placeId = placeId;
    _placeName = name;
    _placeLocation = location;
    // The correction pin starts where the app currently places the place -
    // the tourist moves it to the spot they believe is right.
    _reportLocation = location;
  }

  bool get isConfigured => _placeKind != null && _placeId > 0;

  @override
  Future<void> onInit() async {
    // Registered (and seeded with the last known fix) before anything else -
    // a claim built before the first tick would be stamped invalid.
    locationFacade.register(this);
    _currentLocation = locationFacade.latest;
    if (!isConfigured) {
      setError('No place was selected. Please return to the map.');
    }
  }

  /// Whether the tourist is ON SITE - the silent check behind every claim's
  /// `locationValid` flag (user's design, 2026-09-13).
  ///
  /// The anchor is the PLACE'S ORIGINAL LOCATION - where the app currently
  /// places the landmark/restaurant they are reporting - and it is the same
  /// anchor for every category, an address report included: the tourist has
  /// to actually be at the place. Where they happen to drop the correction
  /// pin has no say in it (a wrong pin is exactly what they may be fixing).
  ///
  /// No fix, or a place without coordinates, means the claim is stored with
  /// `locationValid = false` and quietly never counts.
  bool _isOnsite() =>
      reportLogic.isWithinOnsiteRange(_currentLocation, _placeLocation);

  void selectCategory(ReportCategory category) {
    _selectedCategory = category;
    _formError = null;
    _clearFieldErrors();
    _selectedItem = null;
    if (category == ReportCategory.itemPrice ||
        category == ReportCategory.itemNotExist) {
      _loadItems();
    } else {
      _items = const <ReportableMenuItem>[];
    }
    safeNotifyListeners();
  }

  Future<void> _loadItems() async {
    final ReportPlaceKind? kind = _placeKind;
    if (kind == null) return;
    _itemsLoading = true;
    _itemsError = null;
    safeNotifyListeners();
    try {
      _items = await reportLogic.reportableItemsFor(
        placeKind: kind,
        placeId: _placeId,
      );
    } catch (error) {
      _itemsError =
          'Could not load the menu. Check your connection and try again.';
    } finally {
      _itemsLoading = false;
      safeNotifyListeners();
    }
  }

  void selectItem(ReportableMenuItem item) {
    _selectedItem = item;
    _itemError = null;
    safeNotifyListeners();
  }

  void setPriceText(String value) {
    _priceText = value;
    _priceError = reportLogic.priceError(value);
    _formError = null;
    safeNotifyListeners();
  }

  void setAddressText(String value) {
    // Capped exactly like the form's field (belt-and-suspenders behind the
    // TextField's own maxLength).
    _addressText = _cappedAddress(value);
    _addressError = reportLogic.addressError(_addressText);
    // Their own wording: the field stops following the pin, and the map's
    // version is offered back through `canApplyMapAddress` instead.
    _addressFromMap = false;
    _formError = null;
    _scheduleAddressSearch();
    safeNotifyListeners();
  }

  // --- Corrected location + address (the address report's map) --------------
  //
  // The SAME experience the Add-New-Landmark form gives its address field: an
  // OpenStreetMap with a pin, live suggestions while typing, and the pin's own
  // composed address behind it. The one rule that does NOT carry over is the
  // form's 100 m pin allowance - the app's own pin may be plainly wrong, so a
  // correction can be placed anywhere.

  /// How long the field waits after a keystroke before asking OpenStreetMap -
  /// the same delay the Add-Landmark form uses.
  static const Duration addressSearchDebounce = Duration(milliseconds: 600);
  static const Duration mapAddressLookupDelay = Duration(milliseconds: 500);

  /// Where the correction pin currently sits - the place's own coordinates
  /// until the tourist moves it. Unknown means there is no map to show.
  TouristLocation get reportLocation => _reportLocation;

  /// Suggestions for what is typed in the address field, nearest first.
  List<AddressSuggestion> get addressSuggestions => _addressSuggestions;

  /// Bumped whenever the app itself replaces the field's text (a suggestion,
  /// the map's own address) so the View can re-sync its controller - the same
  /// mechanism the Add-Landmark form uses.
  int get addressVersion => _addressVersion;

  /// Whether the "Use the map pin's address" action has something to offer:
  /// the pin produced an address, it differs from the field, and the field
  /// holds the tourist's own text.
  bool get canApplyMapAddress =>
      !_addressFromMap &&
      _mapDerivedAddress != null &&
      _mapDerivedAddress!.isNotEmpty &&
      _mapDerivedAddress != _addressText;

  /// The address search's status line: searching, unavailable, or nothing
  /// found. Null while idle or when suggestions are showing.
  String? get addressSearchStatus {
    if (_addressSearchRunning) return 'Searching for addresses…';
    if (_addressSearchUnavailable) {
      return 'Address search is unavailable right now. You can still type '
          'the address yourself.';
    }
    if (_addressSearchEmpty) {
      return 'No matching addresses found. You can still type the address '
          'yourself.';
    }
    return null;
  }

  /// The pin lookup's status line: running, or the notice that this spot has
  /// no address to give. Null while idle or after a successful lookup.
  String? get mapAddressStatus {
    if (_mapAddressLookupRunning) return 'Looking up the address…';
    if (_mapAddressUnavailable) {
      return "We couldn't find an address for this spot. Tap the map again, "
          'or type the address yourself.';
    }
    return null;
  }

  /// How a suggestion's distance is labelled ("350 m", "1.2 km") - flat
  /// passthrough to the logic rule, so the View never formats numbers itself.
  String formatDistance(double metres) => reportLogic.formatDistance(metres);

  /// Moves the correction pin to a spot the tourist tapped on the map, and
  /// asks OpenStreetMap for the address behind it: the field follows the pin
  /// until the tourist types their own wording.
  void moveReportLocation(double latitude, double longitude) {
    final TouristLocation target = TouristLocation(
      latitude: latitude,
      longitude: longitude,
    );
    if (!target.isKnown) return;
    _reportLocation = target;
    _clearAddressSearch();
    _scheduleMapAddressLookup();
    safeNotifyListeners();
  }

  /// Picks a suggestion: its text lands in the address field and the pin
  /// follows it (no range rule here - see the section note above).
  void selectAddressSuggestion(AddressSuggestion suggestion) {
    _clearAddressSearch();
    _addressText = _cappedAddress(suggestion.address);
    _addressError = null;
    _addressFromMap = true;
    _addressVersion++;
    moveReportLocation(suggestion.latitude, suggestion.longitude);
  }

  /// Applies the pinned spot's composed address to the field (the "Use the
  /// map pin's address" button) - the tourist chose the map's wording over
  /// their typed text.
  void applyMapAddressFromPin() {
    final String? address = _mapDerivedAddress;
    if (address == null || address.isEmpty) return;
    _addressText = _cappedAddress(address);
    _addressError = null;
    _addressFromMap = true;
    _addressVersion++;
    _clearAddressSearch();
    safeNotifyListeners();
  }

  /// The Add-Landmark form's own ceiling on what the MAP may put in the
  /// field - a composed OpenStreetMap address can run past the cap (typed
  /// text is already capped by the field itself, exactly like the form's).
  String _cappedAddress(String value) {
    final int maxLength = reportLogic.maxAddressLength;
    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  /// Drops every suggestion-search state - used when a pick or the map's own
  /// address settles the field.
  void _clearAddressSearch() {
    _addressSearchDebounce?.cancel();
    _addressSearchToken++;
    _addressSuggestions = const <AddressSuggestion>[];
    _addressSearchRunning = false;
    _addressSearchUnavailable = false;
    _addressSearchEmpty = false;
  }

  /// Schedules the pin's reverse lookup (debounced). No listeners means no
  /// page is watching (pure unit tests must never call the network), and an
  /// unknown pin means there is nothing to look up.
  void _scheduleMapAddressLookup() {
    _mapAddressDebounce?.cancel();
    if (!_reportLocation.isKnown || !hasListeners) return;
    final TouristLocation target = _reportLocation;
    _mapAddressDebounce = Timer(
      mapAddressLookupDelay,
      () => unawaited(_lookupMapAddress(target)),
    );
  }

  Future<void> _lookupMapAddress(TouristLocation target) async {
    _mapAddressLookupRunning = true;
    _mapAddressUnavailable = false;
    safeNotifyListeners();

    String? address;
    try {
      address = await reportLogic.reverseGeocodeAddress(target);
    } catch (_) {
      address = null;
    }

    // The pin may have moved again while this ran - drop a stale answer.
    if (!_sameSpot(_reportLocation, target)) return;

    _mapAddressLookupRunning = false;
    if (address == null || address.isEmpty) {
      _mapAddressUnavailable = true;
      safeNotifyListeners();
      return;
    }

    _mapAddressUnavailable = false;
    _mapDerivedAddress = _cappedAddress(address);
    if (_addressFromMap || _addressText.trim().isEmpty) {
      _addressText = _cappedAddress(address);
      _addressError = null;
      _addressFromMap = true;
      _addressVersion++;
    }
    safeNotifyListeners();
  }

  /// Schedules the suggestion search for the text just typed (debounced,
  /// >= [LandmarkSubmissionLogic.minAddressSearchLength] characters).
  void _scheduleAddressSearch() {
    _addressSearchDebounce?.cancel();
    _addressSearchToken++;
    final String query = _addressText.trim();
    if (query.length < reportLogic.minAddressSearchLength) {
      _addressSuggestions = const <AddressSuggestion>[];
      _addressSearchRunning = false;
      _addressSearchUnavailable = false;
      _addressSearchEmpty = false;
      return;
    }
    if (!hasListeners) return;
    final int token = _addressSearchToken;
    _addressSearchDebounce = Timer(
      addressSearchDebounce,
      () => unawaited(_searchAddresses(query, token)),
    );
  }

  Future<void> _searchAddresses(String query, int token) async {
    if (_addressText.trim() != query) return;
    _addressSearchRunning = true;
    _addressSearchUnavailable = false;
    _addressSearchEmpty = false;
    safeNotifyListeners();

    List<AddressSuggestion>? results;
    try {
      results = await reportLogic.searchAddresses(
        query: query,
        around: _reportLocation.isKnown ? _reportLocation : _placeLocation,
      );
    } catch (_) {
      results = null;
    }

    // A stale response (newer query, or the text changed meanwhile) is
    // dropped silently.
    if (token != _addressSearchToken || _addressText.trim() != query) return;

    _addressSearchRunning = false;
    if (results == null) {
      _addressSuggestions = const <AddressSuggestion>[];
      _addressSearchUnavailable = true;
    } else {
      _addressSuggestions = results;
      _addressSearchEmpty = results.isEmpty;
    }
    safeNotifyListeners();
  }

  static bool _sameSpot(TouristLocation a, TouristLocation b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  @override
  void dispose() {
    _addressSearchDebounce?.cancel();
    _mapAddressDebounce?.cancel();
    locationFacade.unregister(this);
    super.dispose();
  }

  void setClosureAmountText(String value) {
    _closureAmountText = value;
    _closureError = reportLogic.closureError(value, _closureUnit);
    _formError = null;
    safeNotifyListeners();
  }

  void setClosureUnit(ClosureUnit unit) {
    _closureUnit = unit;
    _closureError = reportLogic.closureError(_closureAmountText, _closureUnit);
    safeNotifyListeners();
  }

  // --- Hours editing (same Map<Weekday, List<OpeningHour>> shape the Add
  // Landmark form edits) -----------------------------------------------------

  void setDayStatus(Weekday day, DayStatus status) {
    final List<OpeningHour> updated = <OpeningHour>[
      OpeningHour(id: 0, day: day, status: status),
    ];
    _hours = Map<Weekday, List<OpeningHour>>.of(_hours)..[day] = updated;
    _hoursError = null;
    safeNotifyListeners();
  }

  void addTimeRange(Weekday day) {
    final List<OpeningHour> existing = _hours[day] ?? const <OpeningHour>[];
    _hours = Map<Weekday, List<OpeningHour>>.of(_hours)
      ..[day] = <OpeningHour>[
        ...existing,
        OpeningHour(id: 0, day: day, status: DayStatus.open),
      ];
    _hoursError = null;
    safeNotifyListeners();
  }

  void removeTimeRange(Weekday day, int rangeIndex) {
    final List<OpeningHour> existing = _hours[day] ?? const <OpeningHour>[];
    if (existing.length <= 1) return;
    final List<OpeningHour> updated = List<OpeningHour>.of(existing)
      ..removeAt(rangeIndex);
    _hours = Map<Weekday, List<OpeningHour>>.of(_hours)..[day] = updated;
    _hoursError = null;
    safeNotifyListeners();
  }

  void setRangeTime(
    Weekday day,
    int rangeIndex,
    bool isOpeningTime,
    int minutes,
  ) {
    final List<OpeningHour> existing = _hours[day] ?? const <OpeningHour>[];
    if (rangeIndex >= existing.length) return;
    final OpeningHour current = existing[rangeIndex];
    final int? opening = isOpeningTime ? minutes : current.opensAt;
    int? closing = isOpeningTime ? current.closesAt : minutes;

    // A closing time at or BEFORE the opening time means the NEXT day
    // ("10:00 -> 02:00"): encoded as minutes past midnight + 1440, exactly
    // like the Add-Landmark form - see `OpeningHoursRows`.
    if (opening != null && closing != null) {
      closing = reportLogic.encodeCloseTime(
        opensAt: opening,
        closeMinutes: closing,
      );
    }

    final List<OpeningHour> updated = List<OpeningHour>.of(existing);
    updated[rangeIndex] = OpeningHour(
      id: 0,
      day: day,
      status: DayStatus.open,
      opensAt: opening,
      closesAt: closing,
    );
    _hours = Map<Weekday, List<OpeningHour>>.of(_hours)..[day] = updated;
    _hoursError = null;
    safeNotifyListeners();
  }

  /// Whether the hours form currently has at least one day the tourist
  /// actually changed (any Open/Closed day) - a report with all days Unknown
  /// would submit nothing.
  bool get hasHoursCorrection => _hours.values.any(
    (List<OpeningHour> rows) =>
        rows.any((OpeningHour hour) => hour.status != DayStatus.unknown),
  );

  /// Submits the current form as one claim per specific issue (per corrected
  /// day for hours; one per item for item reports; one for address/closure).
  Future<void> submit() async {
    final ReportPlaceKind? kind = _placeKind;
    final ReportCategory? category = _selectedCategory;
    if (kind == null || category == null || _isSubmitting) return;
    final String? validationError = _validate(category);
    if (validationError != null) {
      _formError = validationError;
      safeNotifyListeners();
      return;
    }
    final List<ReportClaim> claims = _buildClaims(kind, category);
    if (claims.isEmpty) {
      _formError = 'Please fill in the details to report.';
      safeNotifyListeners();
      return;
    }

    _isSubmitting = true;
    _formError = null;
    _requiresSignIn = false;
    _alreadyReported = false;
    _reportFailed = false;
    _reportSubmitted = false;
    _placeHiddenNow = false;
    _appliedMessage = '';
    safeNotifyListeners();

    try {
      final ReportSubmitOutcome outcome = await reportLogic.submitClaims(
        claims: claims,
      );
      if (outcome.requiresSignIn) {
        _requiresSignIn = true;
      } else if (outcome.alreadyReported) {
        _alreadyReported = true;
      } else {
        _reportSubmitted = outcome.submittedCount > 0;
        _placeHiddenNow = outcome.placeHiddenNow;
        if (outcome.applied.isNotEmpty) {
          // An applied correction can change what the map draws: an address
          // moves a pin, corrected hours can change current availability, an
          // item removal can change a food-filtered map, and a closure hides
          // the place. Every live dashboard therefore drops its map caches
          // and re-reads its active view after any applied correction.
          mapRefresh.publishOwnMapDataChanged();
        }
        if (outcome.applied.isNotEmpty) {
          _appliedMessage =
              'Applied: ${outcome.applied.join(', ')}. Thanks for reporting!';
        } else if (outcome.submittedCount > 0) {
          _appliedMessage =
              'Report received. Thank you for helping keep the map accurate.';
        }
      }
    } catch (_) {
      _reportFailed = true;
    } finally {
      _isSubmitting = false;
      safeNotifyListeners();
    }
  }

  String? _validate(ReportCategory category) {
    _clearFieldErrors();
    switch (category) {
      case ReportCategory.operatingHours:
        if (!hasHoursCorrection) {
          _hoursError = 'Change at least one day before submitting.';
        } else {
          _hoursError = reportLogic.operatingHoursError(_hours);
        }
        return _hoursError;
      case ReportCategory.itemPrice:
        if (_selectedItem == null) {
          _itemError = 'Select the menu item whose price is wrong.';
          return _itemError;
        }
        _priceError = reportLogic.priceError(_priceText, required: true);
        return _priceError;
      case ReportCategory.itemNotExist:
        if (_selectedItem == null) {
          _itemError = 'Select the menu item that is no longer available.';
        }
        return _itemError;
      case ReportCategory.address:
        _addressError = reportLogic.addressError(_addressText, required: true);
        return _addressError;
      case ReportCategory.closedPermanently:
        return null;
      case ReportCategory.closedTemporarily:
        _closureError = reportLogic.closureError(
          _closureAmountText,
          _closureUnit,
          required: true,
        );
        return _closureError;
    }
  }

  void _clearFieldErrors() {
    _priceError = null;
    _addressError = null;
    _closureError = null;
    _hoursError = null;
    _itemError = null;
  }

  List<ReportClaim> _buildClaims(
    ReportPlaceKind kind,
    ReportCategory category,
  ) {
    // Every claim carries the silent on-site verdict - only verified claims
    // count toward a threshold (see `_isOnsite`).
    final bool onsiteValid = _isOnsite();
    switch (category) {
      case ReportCategory.operatingHours:
        return <ReportClaim>[
          for (final MapEntry<Weekday, List<OpeningHour>> entry
              in _hours.entries)
            if (entry.value.any(
              (OpeningHour hour) => hour.status != DayStatus.unknown,
            ))
              ReportClaim(
                placeKind: kind,
                placeId: _placeId,
                category: ReportCategory.operatingHours,
                day: entry.key,
                locationValid: onsiteValid,
                payload: reportLogic.hoursPayload(<ProposedDayHours>[
                  for (final OpeningHour hour in entry.value)
                    ProposedDayHours(
                      status: hour.status,
                      opensAt: hour.opensAt,
                      closesAt: hour.closesAt,
                    ),
                ]),
              ),
        ];
      case ReportCategory.itemPrice:
        final ReportableMenuItem? item = _selectedItem;
        final double? price = double.tryParse(_priceText.trim());
        if (item == null || price == null) return const <ReportClaim>[];
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.itemPrice,
            itemKind: item.itemKind,
            itemId: item.id,
            locationValid: onsiteValid,
            payload: reportLogic.pricePayload(price),
          ),
        ];
      case ReportCategory.itemNotExist:
        final ReportableMenuItem? item = _selectedItem;
        if (item == null) return const <ReportClaim>[];
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.itemNotExist,
            itemKind: item.itemKind,
            itemId: item.id,
            locationValid: onsiteValid,
            payload: reportLogic.itemNotExistPayload,
          ),
        ];
      case ReportCategory.address:
        final String address = _addressText.trim();
        if (address.isEmpty) return const <ReportClaim>[];
        // The pin rides along: the text is usually the OpenStreetMap wording
        // for the pin's spot, and OSM addresses are approximate - the pin is
        // the exact part, so the applied fix can move the place with it.
        final bool hasPin = _reportLocation.isKnown;
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.address,
            latitude: hasPin ? _reportLocation.latitude : null,
            longitude: hasPin ? _reportLocation.longitude : null,
            locationValid: onsiteValid,
            payload: reportLogic.addressPayload(address),
          ),
        ];
      case ReportCategory.closedPermanently:
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.closedPermanently,
            locationValid: onsiteValid,
            payload: reportLogic.closedPermanentlyPayload,
          ),
        ];
      case ReportCategory.closedTemporarily:
        final int? amount = int.tryParse(_closureAmountText.trim());
        if (amount == null || amount <= 0) return const <ReportClaim>[];
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.closedTemporarily,
            locationValid: onsiteValid,
            payload: reportLogic.temporaryClosurePayload(
              ProposedClosure(amount: amount, unit: _closureUnit),
            ),
          ),
        ];
    }
  }

  /// Clears the transient report outcome state - the View calls this after
  /// showing the confirmation so a second report starts clean.
  void consumeOutcome() {
    _requiresSignIn = false;
    _alreadyReported = false;
    _reportFailed = false;
    _reportSubmitted = false;
    _placeHiddenNow = false;
    _appliedMessage = '';
    safeNotifyListeners();
  }
}
