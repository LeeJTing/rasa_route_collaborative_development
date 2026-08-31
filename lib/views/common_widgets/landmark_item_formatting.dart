import '../../domain_model/submitted_landmark.dart';

/// "RM20 - RM40", "RM20", or null when [item] carries no price at all.
///
/// Shared between `LandmarkPlaceDetailView`'s `_DishCard` and
/// `LandmarkItemDetailView` - both format the exact same
/// `priceMin`/`priceMax`/`price` fields the same way, so this lives once
/// rather than being copied a second time for the newer screen.
String? landmarkItemPriceLabel(LandmarkItem item) {
  if (item.priceMin > 0 && item.priceMax > 0) {
    return 'RM${_fmt(item.priceMin)} - RM${_fmt(item.priceMax)}';
  }
  final double? price = item.price;
  if (price != null && price > 0) return 'RM${_fmt(price)}';
  return null;
}

String _fmt(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
