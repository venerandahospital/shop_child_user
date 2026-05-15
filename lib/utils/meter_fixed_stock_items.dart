/// Stock at hand for these products is always [kMeterFixedDisplayStockQty].
/// Sales do not reduce it; receives do not increase it
/// (receipt rows still store quantities for costing/history).
library;

const double kMeterFixedDisplayStockQty = 1;

/// Ekiveera white / black polyethylene (name pattern used elsewhere).
bool isEkiveeraPolyethyleneRollItemName(String rawName) {
  final n = rawName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (!n.contains('ekiveera')) return false;
  final white = n.contains('white');
  final black = n.contains('black');
  if (white == black) return false;
  return white || black;
}

/// Ekiveera rolls, carpet, or **Ebinyobwa** (any spelling variant in name, e.g. `Ebinyobwa 1000/=`).
bool isMeterSoldFixedStockItemName(String rawName) {
  if (isEkiveeraPolyethyleneRollItemName(rawName)) return true;
  final lower = rawName.trim().toLowerCase();
  if (lower.contains('carpet')) return true;
  if (lower.contains('ebinyobwa')) return true;
  return false;
}
