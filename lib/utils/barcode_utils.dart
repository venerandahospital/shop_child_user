// Barcode / SKU matching for scanners (exact + partial when digits are obscured).

enum BarcodeScanMatchKind { none, exact, fuzzy }

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
  String scanned, {
  Iterable<String> acceptedBarcodes = const [],
}) {
  if (itemSkuMatchesBarcode(barcode, scanned) ||
      itemSkuMatchesBarcode(sku, scanned)) {
    return true;
  }
  for (final code in acceptedBarcodes) {
    if (itemSkuMatchesBarcode(code, scanned)) return true;
  }
  return false;
}

String barcodeDigitsOnly(String raw) =>
    raw.replaceAll(RegExp(r'\D'), '');

String _barcodeDigitsNormalized(String raw) {
  final digits = barcodeDigitsOnly(raw);
  if (digits.isEmpty) return '';
  final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
  return stripped.isEmpty ? digits : stripped;
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  var prev = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = cur[j - 1] + 1;
      final ins = prev[j] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    prev = cur;
  }
  return prev[n];
}

int _longestCommonSubsequenceLength(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final m = a.length;
  final n = b.length;
  var prev = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    for (var j = 1; j <= n; j++) {
      if (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)) {
        cur[j] = prev[j - 1] + 1;
      } else {
        cur[j] = cur[j - 1] > prev[j] ? cur[j - 1] : prev[j];
      }
    }
    prev = cur;
  }
  return prev[n];
}

bool _isOrderedSubsequence(String shorter, String longer) {
  if (shorter.isEmpty) return false;
  var i = 0;
  for (var k = 0; k < longer.length; k++) {
    if (longer.codeUnitAt(k) == shorter.codeUnitAt(i)) {
      i++;
      if (i == shorter.length) return true;
    }
  }
  return false;
}

/// True when [stored] and [scanned] are mostly the same numeric barcode (e.g. 2–3
/// digits missing or mis-read). Requires at least 6 digits on the shorter side.
bool barcodePartialMatch(String? stored, String scanned) {
  if (itemSkuMatchesBarcode(stored, scanned)) return false;

  final a = _barcodeDigitsNormalized(stored ?? '');
  final b = _barcodeDigitsNormalized(scanned);
  if (a.isEmpty || b.isEmpty) {
    final sa = (stored ?? '').trim().toLowerCase();
    final sb = scanned.trim().toLowerCase();
    if (sa.length < 6 || sb.length < 6) return false;
    return _levenshteinDistance(sa, sb) <= 3;
  }

  final minLen = a.length < b.length ? a.length : b.length;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (minLen < 6) return false;

  final maxEdits = maxLen <= 8 ? 2 : 3;
  if (maxLen - minLen <= maxEdits) {
    if (_levenshteinDistance(a, b) <= maxEdits) return true;
  }

  const minCoverage = 0.84;
  final lcs = _longestCommonSubsequenceLength(a, b);
  if (lcs / minLen >= minCoverage) return true;

  final short = a.length <= b.length ? a : b;
  final long = a.length <= b.length ? b : a;
  if (long.length - short.length <= maxEdits &&
      short.length / long.length >= minCoverage &&
      _isOrderedSubsequence(short, long)) {
    return true;
  }

  return false;
}

/// Fuzzy match only (call after exact match failed).
bool itemBarcodeOrSkuFuzzyMatchesScanned(
  String? barcode,
  String? sku,
  String scanned, {
  Iterable<String> acceptedBarcodes = const [],
}) {
  if (barcodePartialMatch(barcode, scanned) ||
      barcodePartialMatch(sku, scanned)) {
    return true;
  }
  for (final code in acceptedBarcodes) {
    if (barcodePartialMatch(code, scanned)) return true;
  }
  return false;
}

BarcodeScanMatchKind barcodeScanMatchKindForItem({
  required String? barcode,
  required String? sku,
  required String scanned,
  Iterable<String> acceptedBarcodes = const [],
}) {
  if (itemBarcodeOrSkuMatchesScanned(
    barcode,
    sku,
    scanned,
    acceptedBarcodes: acceptedBarcodes,
  )) {
    return BarcodeScanMatchKind.exact;
  }
  if (itemBarcodeOrSkuFuzzyMatchesScanned(
    barcode,
    sku,
    scanned,
    acceptedBarcodes: acceptedBarcodes,
  )) {
    return BarcodeScanMatchKind.fuzzy;
  }
  return BarcodeScanMatchKind.none;
}

/// Exact matches first; otherwise items that partially match the scan.
List<T> itemsMatchingBarcodeScan<T>(
  Iterable<T> items,
  String scanned,
  BarcodeScanMatchKind Function(T item) matchKindFor,
) {
  final exact = <T>[];
  final fuzzy = <T>[];
  for (final item in items) {
    switch (matchKindFor(item)) {
      case BarcodeScanMatchKind.exact:
        exact.add(item);
      case BarcodeScanMatchKind.fuzzy:
        fuzzy.add(item);
      case BarcodeScanMatchKind.none:
        break;
    }
  }
  if (exact.isNotEmpty) return exact;
  return fuzzy;
}
