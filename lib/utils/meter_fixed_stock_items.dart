/// Special roll items (Ekiveera, carpet, ebinyobwa, plus user-defined names):
/// stock is 0 (out) or 1 (one roll on hand). Sales do not deduct stock like normal
/// items; availability is confirmed at checkout. Metres on the roll are tracked
/// separately from stock at hand.
library;

import '../services/special_items_service.dart';

/// Stock at hand when a roll is available to sell.
const double kSpecialItemAvailableStock = 1;

/// Stock at hand when out of stock / roll finished.
const double kSpecialItemUnavailableStock = 0;

@Deprecated('Use kSpecialItemAvailableStock')
const double kMeterFixedDisplayStockQty = kSpecialItemAvailableStock;

/// Ekiveera white / black polyethylene (name pattern used elsewhere).
bool isEkiveeraPolyethyleneRollItemName(String rawName) {
  final n = rawName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (!n.contains('ekiveera')) return false;
  final white = n.contains('white');
  final black = n.contains('black');
  if (white == black) return false;
  return white || black;
}

bool _builtInSpecialItemName(String rawName) {
  if (isEkiveeraPolyethyleneRollItemName(rawName)) return true;
  final lower = rawName.trim().toLowerCase();
  if (lower.contains('carpet')) return true;
  if (lower.contains('ebinyobwa')) return true;
  return false;
}

/// Built-in patterns plus names added on the special-items settings screen.
bool isMeterSoldFixedStockItemName(String rawName) {
  if (_builtInSpecialItemName(rawName)) return true;
  return SpecialItemsService.instance.matchesExtraName(rawName);
}

double specialRollMetersRemaining({
  required double total,
  required double sold,
}) {
  final left = total - sold;
  return left < 0 ? 0 : left;
}
