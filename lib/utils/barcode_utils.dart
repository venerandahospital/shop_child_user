/// True if [sku] stored on an item matches a [scanned] value from a scanner or manual entry.
bool itemSkuMatchesBarcode(String? sku, String scanned) {
  final s = (sku ?? '').trim();
  final t = scanned.trim();
  if (s.isEmpty || t.isEmpty) return false;
  if (s == t) return true;
  final digitOnly = RegExp(r'^\d+$');
  if (digitOnly.hasMatch(s) && digitOnly.hasMatch(t)) {
    final ns = s.replaceFirst(RegExp(r'^0+'), '');
    final nt = t.replaceFirst(RegExp(r'^0+'), '');
    if (ns.isNotEmpty && ns == nt) return true;
  }
  return false;
}

/// Matches [scanned] against an optional product [barcode] and/or internal [sku].
bool itemBarcodeOrSkuMatchesScanned(
  String? barcode,
  String? sku,
  String scanned,
  {Iterable<String> acceptedBarcodes = const []}
) {
  if (itemSkuMatchesBarcode(barcode, scanned) ||
      itemSkuMatchesBarcode(sku, scanned)) {
    return true;
  }
  for (final code in acceptedBarcodes) {
    if (itemSkuMatchesBarcode(code, scanned)) return true;
  }
  return false;
}
