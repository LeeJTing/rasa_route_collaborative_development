import '../../domain_model/submitted_landmark.dart';

/// "RM 20.00", or the "RM 20.00 - RM 40.00" range when the item has no
/// single price, or null when [item] carries no price at all. Always two
/// decimals with a space after "RM", matching the restaurant menu rows'
/// price format (`RestaurantMenuPreview`).
///
/// The ITEM PRICE wins over Gemini's min/max suggestion (user request: the
/// landmark page's "Local Foods Served" rows show the price the place
/// charges, not a range) - the range is only a fallback for a row saved
/// without a price.
///
/// Shared between `LandmarkPlaceDetailView`'s dish rows and
/// `LandmarkItemDetailView` - both format the exact same
/// `priceMin`/`priceMax`/`price` fields the same way, so this lives once
/// rather than being copied a second time for the newer screen.
String? landmarkItemPriceLabel(LandmarkItem item) {
  final double? price = item.price;
  if (price != null && price > 0) return 'RM ${_fmt(price)}';
  if (item.priceMin > 0 && item.priceMax > 0) {
    return 'RM ${_fmt(item.priceMin)} - RM ${_fmt(item.priceMax)}';
  }
  return null;
}

String _fmt(double value) => value.toStringAsFixed(2);
