import '../../domain_model/submitted_landmark.dart';

/// "RM 20.00 - RM 40.00", "RM 20.00", or null when [item] carries no price
/// at all. Always two decimals with a space after "RM", matching the
/// restaurant menu rows' price format (`RestaurantMenuPreview`) so both
/// place pages display prices the same way.
///
/// Shared between `LandmarkPlaceDetailView`'s dish rows and
/// `LandmarkItemDetailView` - both format the exact same
/// `priceMin`/`priceMax`/`price` fields the same way, so this lives once
/// rather than being copied a second time for the newer screen.
String? landmarkItemPriceLabel(LandmarkItem item) {
  if (item.priceMin > 0 && item.priceMax > 0) {
    return 'RM ${_fmt(item.priceMin)} - RM ${_fmt(item.priceMax)}';
  }
  final double? price = item.price;
  if (price != null && price > 0) return 'RM ${_fmt(price)}';
  return null;
}

String _fmt(double value) => value.toStringAsFixed(2);
