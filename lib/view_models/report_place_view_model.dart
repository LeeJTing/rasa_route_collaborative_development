import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/opening_hour.dart';
import '../domain_model/report_category.dart';
import '../domain_model/report_claim.dart';
import '../domain_model/report_outcome.dart';
import '../model/business_logic/report_logic_facade.dart';
import 'update_restaurant_facade.dart';

/// Singleton hand-off that carries which place the report page is about from
/// the detail screen to `ReportPlaceView` - the same read-and-clear pattern
/// `MapSelectionHandoff` / `LandmarkDraftHandoff` use (routes pass no
/// arguments, ViewModels take no constructor parameters).
class ReportPlaceHandoff {
  factory ReportPlaceHandoff() => _instance;

  ReportPlaceHandoff._();

  static final ReportPlaceHandoff _instance = ReportPlaceHandoff._();

  ReportPlaceKind? pendingKind;
  int? pendingPlaceId;
  String pendingName = '';

  (ReportPlaceKind, int, String)? take() {
    final ReportPlaceKind? kind = pendingKind;
    final int? placeId = pendingPlaceId;
    if (kind == null || placeId == null) return null;
    final (ReportPlaceKind, int, String) value = (kind, placeId, pendingName);
    pendingKind = null;
    pendingPlaceId = null;
    pendingName = '';
    return value;
  }
}

/// ViewModel for the full-screen report page (`ReportPlaceView`), shared by
/// catalogue restaurants and submitted landmarks. The tourist picks a
/// category, enters the correction, and the page submits one claim per
/// specific issue (per corrected day for hours; per item for item reports).
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else;
///   * state goes in private fields with read-only getters.
class ReportPlaceViewModel extends BaseViewModel {
  ReportPlaceViewModel();

  @protected
  ReportLogicFacade createReportLogic() => ReportLogicFacade();

  late final ReportLogicFacade reportLogic = createReportLogic();

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

  /// How many identical claims are needed to auto-apply this category - shown
  /// on the page so the tourist knows the fix isn't instant.
  int thresholdFor(ReportCategory category) =>
      reportLogic.thresholdFor(category);

  /// Set from `ReportPlaceHandoff` in the View's `initState` before onInit.
  void configure(ReportPlaceKind kind, int placeId, String name) {
    _placeKind = kind;
    _placeId = placeId;
    _placeName = name;
  }

  bool get isConfigured => _placeKind != null && _placeId > 0;

  @override
  Future<void> onInit() async {
    if (!isConfigured) {
      setError('No place was selected. Please return to the map.');
    }
  }

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
    _addressText = value;
    _addressError = reportLogic.addressError(value);
    _formError = null;
    safeNotifyListeners();
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
        if (outcome.placeHiddenNow) {
          // The place is no longer 'available' - every live dashboard drops
          // its caches and re-reads so the hidden pin disappears.
          mapRefresh.publishOwnMapDataChanged();
        }
        if (outcome.applied.isNotEmpty) {
          _appliedMessage =
              'Applied: ${outcome.applied.join(', ')}. Thanks for reporting!';
        } else if (outcome.submittedCount > 0) {
          _appliedMessage =
              'Report received. It needs ${thresholdFor(category)} matching '
              'reports before the change is applied.';
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
            payload: reportLogic.itemNotExistPayload,
          ),
        ];
      case ReportCategory.address:
        final String address = _addressText.trim();
        if (address.isEmpty) return const <ReportClaim>[];
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.address,
            payload: reportLogic.addressPayload(address),
          ),
        ];
      case ReportCategory.closedPermanently:
        return <ReportClaim>[
          ReportClaim(
            placeKind: kind,
            placeId: _placeId,
            category: ReportCategory.closedPermanently,
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
