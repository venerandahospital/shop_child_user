import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/item.dart';
import '../utils/barcode_utils.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'barcode_scan_screen.dart';

String _unitDisplay(Item e) {
  final name = (e.unit ?? '').trim();
  if (name.isNotEmpty) return name;
  return (e.unitShort ?? '').trim();
}

bool _sameItem(Item? a, Item? b) {
  if (a == null || b == null) return false;
  if (a.id != null && b.id != null) return a.id == b.id;
  return identical(a, b);
}

bool _itemMatchesQuery(Item e, String trimmedRaw) {
  final t = trimmedRaw.trim();
  if (t.isEmpty) return true;
  if (barcodeScanMatchKindForItem(barcode: e.barcode, sku: e.sku, scanned: t) !=
      BarcodeScanMatchKind.none) {
    return true;
  }
  final q = t.toLowerCase();
  final parts = <String>[e.name.toLowerCase()];
  final sku = (e.sku ?? '').trim().toLowerCase();
  if (sku.isNotEmpty) parts.add(sku);
  final bc = (e.barcode ?? '').trim().toLowerCase();
  if (bc.isNotEmpty) parts.add(bc);
  final cat = (e.category ?? '').trim().toLowerCase();
  if (cat.isNotEmpty) parts.add(cat);
  final u = _unitDisplay(e).toLowerCase();
  if (u.isNotEmpty) parts.add(u);
  return parts.any((p) => p.contains(q));
}

/// Full-screen searchable list to pick one [Item]. Avoids modal bottom-sheet
/// disposal issues with large lists and text fields.
class ItemSearchPickScreen extends StatefulWidget {
  const ItemSearchPickScreen({
    super.key,
    required this.title,
    required this.options,
    this.selected,
  });

  final String title;
  final List<Item> options;
  final Item? selected;

  /// Returns the chosen item, or `null` if the user backs out without choosing.
  static Future<Item?> pick(
    BuildContext context, {
    required String title,
    required List<Item> options,
    Item? selected,
  }) {
    if (options.isEmpty) {
      return Future<Item?>.value(null);
    }
    return Navigator.of(context).push<Item?>(
      MaterialPageRoute<Item?>(
        builder: (_) => ItemSearchPickScreen(
          title: title,
          options: options,
          selected: selected,
        ),
      ),
    );
  }

  @override
  State<ItemSearchPickScreen> createState() => _ItemSearchPickScreenState();
}

class _ItemSearchPickScreenState extends State<ItemSearchPickScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barcode scanning works on Android and iOS devices.'),
        ),
      );
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (!mounted || code == null) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    setState(() => _search.text = trimmed);
    _searchFocus.requestFocus();
    final hits = itemsMatchingBarcodeScan<Item>(
      widget.options,
      trimmed,
      (e) => barcodeScanMatchKindForItem(
        barcode: e.barcode,
        sku: e.sku,
        scanned: trimmed,
      ),
    );
    if (hits.length == 1) {
      if (!mounted) return;
      Navigator.of(context).pop<Item?>(hits.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _search.text.trim();
    final filtered = t.isEmpty
        ? widget.options
        : widget.options.where((e) => _itemMatchesQuery(e, t)).toList();

    return Scaffold(
      appBar: AppBar(
        title: SectionPageTitle(pageTitle: widget.title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search by name, SKU, barcode…',
                      prefixIcon: Icon(Icons.search, size: 22),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Scan barcode',
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner_outlined, size: 26),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching items',
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filtered.length,
                    separatorBuilder: (context, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      final isSel = _sameItem(widget.selected, item);
                      return ListTile(
                        selected: isSel,
                        title: Text(
                          toTitleCaseWords(item.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'AV ${formatDisplayNumber(item.stockQty)} ${_unitDisplay(item)}',
                        ),
                        trailing: isSel
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.of(context).pop<Item?>(item);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
