import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/barcode_utils.dart';
import 'barcode_scan_screen.dart';
import 'stock_receipts_list_screen.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';

class ReceiveStockScreen extends StatefulWidget {
  const ReceiveStockScreen({super.key, this.initialItemId});

  final int? initialItemId;

  @override
  State<ReceiveStockScreen> createState() => _ReceiveStockScreenState();
}

class _ReceiveStockScreenState extends State<ReceiveStockScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  final _qtyController = TextEditingController();
  final _totalCostController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _brandController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Item> _items = [];
  Map<int, List<String>> _itemBarcodeAliases = const {};
  Item? _selectedItem;
  DateTime? _receiveDate;
  DateTime? _expiryDate;
  String _currencySymbol = 'USh';
  bool _syncingCosts = false;
  bool _lastEditedUnitCost = false;

  @override
  void initState() {
    super.initState();
    _receiveDate = DateTime.now();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadItems();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _qtyController.dispose();
    _totalCostController.dispose();
    _unitCostController.dispose();
    _sellingPriceController.dispose();
    _brandController.dispose();
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
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    Map<int, List<String>> aliases = const {};
    if (!isRemote) {
      final ids = items.map((e) => e.id).whereType<int>();
      aliases = await _db.getItemBarcodesMap(itemIds: ids);
    }
    if (!mounted) return;
    Item? selected;
    if (items.isNotEmpty) {
      if (widget.initialItemId != null) {
        final byId = items.where((e) => e.id == widget.initialItemId).toList();
        if (byId.isNotEmpty) selected = byId.first;
      } else if (_selectedItem != null) {
        final same = items.where((e) => e.id == _selectedItem!.id).toList();
        if (same.isNotEmpty) selected = same.first;
      }
    }
    setState(() {
      _items = items;
      _itemBarcodeAliases = aliases;
      _selectedItem = selected;
      if (_selectedItem != null && _sellingPriceController.text.trim().isEmpty) {
        _sellingPriceController.text = formatMoney(_selectedItem!.sellingPrice);
      }
      _loading = false;
    });
  }

  Future<void> _scanAndSelectItem() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barcode scanning works on Android and iOS devices.'),
        ),
      );
      return;
    }
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (!mounted || scanned == null) return;
    final code = scanned.trim();
    if (code.isEmpty) return;
    final matched = _items.where((item) {
      return itemBarcodeOrSkuMatchesScanned(
        item.barcode,
        item.sku,
        code,
        acceptedBarcodes: _itemBarcodeAliases[item.id ?? -1] ?? const [],
      );
    }).toList();
    if (matched.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No item found for scanned barcode/SKU.')),
      );
      return;
    }
    final item = matched.first;
    setState(() {
      _selectedItem = item;
      _sellingPriceController.text = formatMoney(item.sellingPrice);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected item: ${item.name}')),
    );
  }

  double get _qty =>
      double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0;
  double get _totalCost =>
      double.tryParse(_totalCostController.text.replaceAll(',', '.')) ?? 0;
  double get _unitCostInput =>
      double.tryParse(_unitCostController.text.replaceAll(',', '.')) ?? 0;

  void _setCostText(TextEditingController controller, double value) {
    final next = value <= 0
        ? ''
        : formatDisplayNumber(value, fractionDigits: 6, fixedDecimals: false);
    if (controller.text == next) return;
    _syncingCosts = true;
    controller.text = next;
    _syncingCosts = false;
  }

  void _recomputeFromTotal() {
    final qty = _qty;
    if (qty <= 0) {
      _setCostText(_unitCostController, 0);
      return;
    }
    _setCostText(_unitCostController, _totalCost / qty);
  }

  void _recomputeFromUnit() {
    final qty = _qty;
    if (qty <= 0) {
      _setCostText(_totalCostController, 0);
      return;
    }
    _setCostText(_totalCostController, _unitCostInput * qty);
  }

  void _onQtyChanged() {
    if (_syncingCosts) return;
    if (_lastEditedUnitCost) {
      _recomputeFromUnit();
    } else {
      _recomputeFromTotal();
    }
    if (mounted) setState(() {});
  }

  void _onTotalCostChanged() {
    if (_syncingCosts) return;
    _lastEditedUnitCost = false;
    _recomputeFromTotal();
    if (mounted) setState(() {});
  }

  void _onUnitCostChanged() {
    if (_syncingCosts) return;
    _lastEditedUnitCost = true;
    _recomputeFromUnit();
    if (mounted) setState(() {});
  }

  double? _parsePositiveQuantity() {
    final raw = _qtyController.text.trim();
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _save() async {
    final item = _selectedItem;
    if (item == null || item.id == null || item.id! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a valid item before saving')),
      );
      return;
    }
    final qty = _parsePositiveQuantity();
    if (qty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter quantity as a positive number')),
      );
      return;
    }
    final totalCost = _totalCost;
    final unitCost = _unitCostInput;
    final effectiveUnitCost =
        unitCost > 0 ? unitCost : (qty > 0 ? totalCost / qty : 0);
    final sellingPrice =
        double.tryParse(_sellingPriceController.text.replaceAll(',', '.')) ??
            item.sellingPrice;
    if (effectiveUnitCost > 0 && sellingPrice <= effectiveUnitCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selling price must be greater than cost price.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (await _auth.isRemoteUser()) {
        final remote = await _auth.receiveRemoteStock({
          'itemId': item.id,
          'quantity': qty,
          'unitCost': unitCost > 0 ? unitCost : null,
          'totalCost': totalCost > 0 ? totalCost : null,
          'sellingPrice': sellingPrice,
          'brand': _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
          'expiryDate': _expiryDate?.toIso8601String(),
          'storeId': item.storeId,
        });
        if (remote['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((remote['message'] ?? 'Failed to sync receive stock').toString())),
          );
          return;
        }
        await _loadItems();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stock received successfully')));
        Navigator.of(context).pop(true);
        return;
      }
      await _db.receiveStock(
        itemId: item.id!,
        quantity: qty,
        unitCost: unitCost > 0 ? unitCost : null,
        totalCost: totalCost,
        sellingPrice: sellingPrice,
        brand: _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
        expiryDate: _expiryDate,
        receivedAt: _receiveDate,
        storeId: item.storeId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stock received successfully')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to receive stock: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _selectedItem;
    final unit = (item?.unitShort ?? item?.unit ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Receive stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'This item adjustments',
            onPressed: () {
              final selected = _selectedItem;
              if (selected?.id == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select an item first.')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => StockReceiptsListScreen(
                    itemId: selected!.id,
                    itemName: selected.name,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Receive records',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StockReceiptsListScreen(),
                ),
              );
            },
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
                      Center(child: Text('No items found. Add items first on Items page.')),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<Item>(
                              initialValue: item,
                              decoration: const InputDecoration(labelText: 'Item'),
                              isExpanded: true,
                              items: _items
                                  .map(
                                    (e) => DropdownMenuItem<Item>(
                                      value: e,
                                      child: Text(
                                        '${e.name}  •  ${formatDisplayNumber(e.stockQty)} ${(e.unitShort ?? e.unit ?? '').trim()}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedItem = value;
                                  _sellingPriceController.text =
                                      formatMoney(value.sellingPrice);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Scan barcode/QR to select item',
                            onPressed: _scanAndSelectItem,
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (item != null)
                        Text(
                          'Current stock: ${formatDisplayNumber(item.stockQty)} $unit',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      if (item != null) const SizedBox(height: 6),
                      if (item != null)
                        Text(
                          'Current selling price: $_currencySymbol${formatMoney(item.sellingPrice)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _qtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: unit.isEmpty ? 'Quantity received' : 'Quantity received ($unit)',
                        ),
                        onChanged: (_) => _onQtyChanged(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _unitCostController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Unit cost',
                          prefixText: '$_currencySymbol ',
                        ),
                        onChanged: (_) => _onUnitCostChanged(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _totalCostController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total cost',
                          prefixText: '$_currencySymbol ',
                        ),
                        onChanged: (_) => _onTotalCostChanged(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Unit cost and total cost auto-calculate from each other using quantity.',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _sellingPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Selling price after receive',
                          prefixText: '$_currencySymbol ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _brandController,
                        decoration: const InputDecoration(labelText: 'Brand (optional)'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _receiveDate ?? now,
                            firstDate: now.subtract(const Duration(days: 3650)),
                            lastDate: now.add(const Duration(days: 3650)),
                          );
                          if (picked == null) return;
                          setState(() => _receiveDate = picked);
                        },
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(
                          _receiveDate == null
                              ? 'Receive date: Today'
                              : 'Receive date: ${_fmtDate(_receiveDate!)}',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _expiryDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (picked == null) return;
                          setState(() => _expiryDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _expiryDate == null
                              ? 'Set expiry date (optional)'
                              : 'Expiry date: ${_fmtDate(_expiryDate!)}',
                        ),
                      ),
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
                          label: Text(_saving ? 'Saving...' : 'Save receive'),
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

