import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/meter_fixed_stock_items.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'stock_receipts_list_screen.dart';

enum _AdjustmentType { add, remove }

class StockAdjustmentScreen extends StatefulWidget {
  const StockAdjustmentScreen({super.key, this.initialItemId});

  final int? initialItemId;

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Item> _items = [];
  Item? _selectedItem;
  _AdjustmentType _type = _AdjustmentType.add;
  String _currencySymbol = 'USh';

  @override
  void initState() {
    super.initState();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadItems();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final items = isRemote
        ? await RemoteSyncService.instance.fetchItems()
        : await _db.getItems();
    if (!mounted) return;
    Item? selected;
    if (items.isNotEmpty) {
      selected = items.first;
      if (widget.initialItemId != null) {
        for (final item in items) {
          if (item.id == widget.initialItemId) {
            selected = item;
            break;
          }
        }
      }
    }
    setState(() {
      _items = items;
      _selectedItem = selected;
      _loading = false;
    });
  }

  double get _qty =>
      double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0;

  double get _signedDelta =>
      _type == _AdjustmentType.remove ? -_qty : _qty;

  double get _previewStock {
    final current = _selectedItem?.stockQty ?? 0;
    final next = current + _signedDelta;
    return next < 0 ? 0 : next;
  }

  String _saleCategoryLabel(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return 'Retail';
    for (final part in raw.split('|').map((p) => p.trim())) {
      if (part.toLowerCase().startsWith('sale:')) {
        final value = part.substring(part.indexOf(':') + 1).trim();
        if (value.isNotEmpty) return toTitleCaseWords(value);
      }
    }
    return 'Retail';
  }

  String _itemPickerLabel(Item item) {
    final unit = (item.unit ?? item.unitShort ?? '').trim();
    final sale = _saleCategoryLabel(item);
    final parts = <String>[
      toTitleCaseWords(item.name),
      sale,
      if (unit.isNotEmpty) toTitleCaseWords(unit),
    ];
    return parts.join(' - ');
  }

  Future<void> _save() async {
    final item = _selectedItem;
    if (item == null || item.id == null) return;
    final qty = _qty;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter adjustment quantity')),
      );
      return;
    }
    if (_type == _AdjustmentType.remove &&
        !isMeterSoldFixedStockItemName(item.name) &&
        qty > item.stockQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough stock. Max is ${formatDisplayNumber(item.stockQty)}.',
          ),
        ),
      );
      return;
    }

    final delta = _type == _AdjustmentType.remove ? -qty : qty;
    final reason = _reasonController.text.trim();
    final brandTag = reason.isEmpty ? 'ADJ|' : 'ADJ|$reason';

    setState(() => _saving = true);
    try {
      if (await _auth.isRemoteUser()) {
        final remote = await _auth.adjustRemoteStock({
          'itemId': item.id,
          'quantity': qty,
          'type': _type == _AdjustmentType.remove ? 'remove' : 'add',
          'reason': reason,
        });
        if (remote['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (remote['message'] ?? 'Failed to adjust stock').toString(),
              ),
            ),
          );
          return;
        }
      }
      await _db.receiveStock(
        itemId: item.id!,
        quantity: delta,
        unitCost: item.costPrice,
        totalCost: item.costPrice * delta,
        sellingPrice: item.sellingPrice,
        brand: brandTag,
        receivedAt: DateTime.now(),
        storeId: item.storeId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock adjusted successfully')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to adjust stock: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openAdjustmentsForItem() {
    final item = _selectedItem;
    if (item?.id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select an item first.')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockReceiptsListScreen(
          itemId: item!.id,
          itemName: item.name,
          adjustmentOnly: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _selectedItem;
    final unit = (item?.unitShort ?? item?.unit ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Stock Adjustment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'View item adjustments',
            onPressed: _openAdjustmentsForItem,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadItems,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No items found. Add items first.')),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<Item>(
                    initialValue: item,
                    decoration: const InputDecoration(labelText: 'Item'),
                    isExpanded: true,
                    items: _items
                        .map(
                          (e) => DropdownMenuItem<Item>(
                            value: e,
                            child: Text(
                              _itemPickerLabel(e),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedItem = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<_AdjustmentType>(
                          value: _AdjustmentType.add,
                          groupValue: _type,
                          title: const Text('Add stock'),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _type = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<_AdjustmentType>(
                          value: _AdjustmentType.remove,
                          groupValue: _type,
                          title: const Text('Remove stock'),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _type = v!),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          'Quantity ${unit.isNotEmpty ? '($unit)' : ''}',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (item != null) ...[
                    Text(
                      'Current stock: ${formatDisplayNumber(item.stockQty)} ${unit.trim()}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'After adjustment: ${formatDisplayNumber(_previewStock)} ${unit.trim()}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cost price: $_currencySymbol${formatMoney(item.costPrice)}',
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save adjustment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

