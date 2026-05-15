import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/mother_data_cache.dart';
import '../services/remote_sync_service.dart';
import '../utils/barcode_utils.dart';
import '../utils/number_display.dart';
import '../utils/meter_fixed_stock_items.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'barcode_scan_screen.dart';
import 'barcode_labels_screen.dart';
import 'receive_stock_screen.dart';
import 'stock_receipts_list_screen.dart';
import 'item_transactions_screen.dart';
import 'stock_transfer_screen.dart';
import 'item_edit_screen.dart';
import 'item_details_screen.dart';
import 'stock_adjustment_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;
  final _searchController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  bool _loading = true;
  List<Item> _items = [];
  Map<int, List<String>> _itemBarcodeAliases = const {};
  List<Item> _filteredItems = [];
  String _currencySymbol = 'USh';
  bool _hideItemImages = true;
  bool _speechReady = false;
  bool _isListening = false;
  late final TabController _saleTabController;

  @override
  void initState() {
    super.initState();
    _saleTabController = TabController(length: 4, vsync: this, initialIndex: 0);
    _saleTabController.addListener(() {
      if (_saleTabController.indexIsChanging) return;
      setState(() {
        _filteredItems = _filterItems(_items, _searchController.text);
      });
    });
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadItems();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _speech.stop();
    _saleTabController.dispose();
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    if (!isRemote) {
      await _db.ensureGeneratedPrimaryCodesAndMoveLegacyCodes();
    }
    final items = isRemote
        ? await RemoteSyncService.instance.fetchItems()
        : await _db.getItems();
    final Map<int, List<String>> aliases = isRemote
        ? MotherDataCache.instance.getItemBarcodeAliasesMap()
        : await _db.getItemBarcodesMap(
            itemIds: items.map((e) => e.id).whereType<int>(),
          );
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _items = items;
      _itemBarcodeAliases = aliases;
      _filteredItems = _filterItems(items, _searchController.text);
      _loading = false;
    });
  }

  void _applyFilter() {
    setState(() {
      _filteredItems = _filterItems(_items, _searchController.text);
    });
  }

  Future<void> _scanBarcodeIntoSearch() async {
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
    _searchController.text = trimmed;
    _applyFilter();
  }

  Future<void> _toggleVoiceSearch() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice search is available on Android and iOS.')),
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }
    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please allow microphone permission for voice search.')),
      );
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isListening = false);
        },
      );
    }
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start voice search on this device.')),
      );
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        _searchController.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _isListening = false);
        } else {
          _applyFilter();
        }
      },
    );
  }

  String _itemSaleSlug(Item item) {
    final raw = (item.category ?? '').trim().toLowerCase();
    if (raw.contains('sale: wholesale')) return 'wholesale';
    if (raw.contains('sale: service')) return 'service';
    return 'retail';
  }

  bool _itemMatchesSelectedTab(Item item) {
    final selectedSaleTab = _saleTabController.index;
    final slug = _itemSaleSlug(item);
    if (selectedSaleTab == 0) return slug != 'service'; // all (exclude service)
    if (selectedSaleTab == 1) return slug == 'retail';
    if (selectedSaleTab == 2) return slug == 'wholesale';
    return slug == 'service';
  }

  List<Item> _filterItems(List<Item> source, String rawQuery) {
    final trimmed = rawQuery.trim();
    final query = trimmed.toLowerCase();
    return source.where((item) {
      if (!_itemMatchesSelectedTab(item)) return false;
      if (query.isEmpty) return true;
      final name = item.name.toLowerCase();
      final sku = (item.sku ?? '').toLowerCase();
      final barcode = (item.barcode ?? '').toLowerCase();
      final category = (item.category ?? '').toLowerCase();
      if (barcodeScanMatchKindForItem(
            barcode: item.barcode,
            sku: item.sku,
            scanned: trimmed,
            acceptedBarcodes:
                _itemBarcodeAliases[item.id ?? -1] ?? const [],
          ) !=
          BarcodeScanMatchKind.none) {
        return true;
      }
      return name.contains(query) ||
          sku.contains(query) ||
          barcode.contains(query) ||
          category.contains(query);
    }).toList();
  }

  Future<void> _showItemDialog({Item? item}) async {
    final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ItemEditScreen(item: item),
          ),
        ) ??
        false;

    if (changed) {
      await _loadItems();
    }
  }

  Future<void> _deleteItem(Item item) async {
    if (item.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text(
          'Delete "${toTitleCaseWords(item.name)}" from this section inventory? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (await _auth.isRemoteUser()) {
      final remote = await _auth.deleteRemoteItem(item.id!);
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (remote['message'] ?? 'Failed to delete item on mother').toString(),
            ),
          ),
        );
        return;
      }
      await _loadItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${toTitleCaseWords(item.name)}" deleted')),
      );
      return;
    }
    await _db.deleteItem(item.id!);
    await _loadItems();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${toTitleCaseWords(item.name)}" deleted')),
    );
  }

  Future<void> _showImagePreview({
    required String imageUrl,
    required String itemName,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    height: 220,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Could not load image',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
              ),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              child: Text(
                toTitleCaseWords(itemName),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isWholesaleSaleItem(Item item) {
    final category = (item.category ?? '').toLowerCase();
    return category.contains('sale: wholesale');
  }

  bool _canTransfer(Item item) {
    return _isWholesaleSaleItem(item) && item.stockQty > 0;
  }

  bool _isServiceSaleItem(Item item) => _itemSaleSlug(item) == 'service';

  String _saleCategoryLabel(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw.split('|').map((p) => p.trim());
    for (final part in parts) {
      if (part.toLowerCase().startsWith('sale:')) {
        return part.substring(5).trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Items'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(102),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TabBar(
                  controller: _saleTabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'All Items'),
                    Tab(text: 'Retail'),
                    Tab(text: 'Wholesale'),
                    Tab(text: 'Service'),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: theme.textTheme.bodySmall,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  prefixIcon: const Icon(Icons.search, size: 18),
                                  hintText: 'Search items by name, barcode, SKU, or category',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Scan barcode',
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: _scanBarcodeIntoSearch,
                                  child: const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(Icons.qr_code_scanner, size: 20),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: _isListening ? 'Stop voice search' : 'Voice search',
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: _toggleVoiceSearch,
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(
                                      _isListening ? Icons.mic : Icons.mic_none,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isListening)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mic, color: Colors.white, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Listening...',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: _scanBarcodeIntoSearch,
          ),
          IconButton(
            icon: Icon(
              _hideItemImages ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
            tooltip: _hideItemImages ? 'Show item images' : 'Hide item images',
            onPressed: () {
              setState(() => _hideItemImages = !_hideItemImages);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
          ),
          IconButton(
            icon: const Icon(Icons.move_to_inbox),
            tooltip: 'Receive records',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StockReceiptsListScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print barcode labels',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BarcodeLabelsScreen(items: _items),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadItems,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  _miniInfoChip(
                    context,
                    label: 'Items',
                    value: '${_items.length}',
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _miniInfoChip(
                    context,
                    label: 'Low',
                    value: '${_items.where((e) => e.isBelowReorder && !e.isOutOfStock).length}',
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  _miniInfoChip(
                    context,
                    label: 'Out',
                    value: '${_items.where((e) => e.isOutOfStock).length}',
                    color: Colors.red,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text('No items yet. Add your first item.'),
                            ),
                          ],
                        )
                      : _filteredItems.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text('No items match your search.'),
                                ),
                              ],
                            )
                          : ListView.builder(
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isServiceItem = _isServiceSaleItem(item);
                      final isLowStock = item.isBelowReorder;
                      final isOutOfStock = item.isOutOfStock;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        elevation: 1.2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                              if (!_hideItemImages) ...[
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: (item.imageUrl ?? '').trim().isEmpty
                                      ? null
                                      : () => _showImagePreview(
                                            imageUrl: item.imageUrl!.trim(),
                                            itemName: item.name,
                                          ),
                                  child: Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: (item.imageUrl ?? '').trim().isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(
                                              item.imageUrl!,
                                              width: 58,
                                              height: 58,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Text(
                                                item.name.isNotEmpty
                                                    ? item.name
                                                          .substring(0, 1)
                                                          .toUpperCase()
                                                    : '?',
                                                style: theme.textTheme.titleMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Text(
                                            item.name.isNotEmpty
                                                ? item.name
                                                      .substring(0, 1)
                                                      .toUpperCase()
                                                : '?',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ItemDetailsScreen(
                                              item: item,
                                              currencySymbol: _currencySymbol,
                                            ),
                                          ),
                                        );
                                      },
                                      child: RichText(
                                        text: TextSpan(
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.primary,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: toTitleCaseWords(item.name),
                                            ),
                                            if ((item.unit ?? '').trim().isNotEmpty)
                                              TextSpan(
                                                text: ' (${item.unit!.trim()})',
                                                style:
                                                    theme.textTheme.bodySmall?.copyWith(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: theme.colorScheme.primary
                                                      .withValues(alpha: 0.85),
                                                ),
                                              ),
                                            if (_saleCategoryLabel(item).isNotEmpty)
                                              TextSpan(
                                                text:
                                                    ' - ${_saleCategoryLabel(item)}',
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if ((item.category ?? '').trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          item.category!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: Colors.grey[700]),
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Sell: $_currencySymbol${formatMoney(item.sellingPrice)}  •  Cost: $_currencySymbol${formatMoney(item.costPrice)}',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if ((item.shelfNumber ?? '').trim().isNotEmpty)
                                          _statusChip(
                                            context,
                                            'Shelf ${item.shelfNumber!.trim()}',
                                            Colors.teal,
                                          ),
                                        if (isMeterSoldFixedStockItemName(item.name) &&
                                            item.specialRollMetersTotal > 0)
                                          _statusChip(
                                            context,
                                            'Roll left ${formatDisplayNumber(item.specialRollMetersRemaining)}',
                                            Colors.deepPurple,
                                          ),
                                        if (!isServiceItem) ...[
                                          _stockStatusChip(
                                            context,
                                            stock: formatDisplayNumber(item.stockQty),
                                            unit: item.unit ?? '',
                                          ),
                                          if (isOutOfStock)
                                            _statusChip(
                                              context,
                                              'Out of stock',
                                              Colors.red,
                                            )
                                          else if (isLowStock)
                                            _statusChip(
                                              context,
                                              'Low stock',
                                              Colors.orange,
                                            ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (!isServiceItem) ...[
                                    IconButton(
                                      icon: const Icon(Icons.add_box_outlined),
                                      tooltip: 'Receive stock',
                                      onPressed: () async {
                                        final changed = await Navigator.of(context).push<bool>(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ReceiveStockScreen(initialItemId: item.id),
                                          ),
                                        );
                                        if (changed == true) {
                                          await _loadItems();
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.receipt_long_outlined),
                                      tooltip: 'Stock transactions',
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ItemTransactionsScreen(item: item),
                                          ),
                                        );
                                      },
                                    ),
                                    if (_canTransfer(item))
                                      IconButton(
                                        icon: const Icon(Icons.swap_horiz),
                                        tooltip: 'Transfer stock',
                                        onPressed: () async {
                                          final changed = await Navigator.of(context).push<bool>(
                                            MaterialPageRoute(
                                              builder: (_) => StockTransferScreen(
                                                initialFromItemId: item.id,
                                              ),
                                            ),
                                          );
                                          if (changed == true) {
                                            await _loadItems();
                                          }
                                        },
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.tune),
                                      tooltip: 'Stock adjustment',
                                      onPressed: () async {
                                        final changed = await Navigator.of(context).push<bool>(
                                          MaterialPageRoute(
                                            builder: (_) => StockAdjustmentScreen(
                                              initialItemId: item.id,
                                            ),
                                          ),
                                        );
                                        if (changed == true) {
                                          await _loadItems();
                                        }
                                      },
                                    ),
                                  ],
                                  IconButton(
                                    icon: const Icon(Icons.edit_square),
                                    tooltip: 'Edit item',
                                    onPressed: () => _showItemDialog(item: item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Delete item',
                                    onPressed: () => _deleteItem(item),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showItemDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _miniInfoChip(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _stockStatusChip(
    BuildContext context, {
    required String stock,
    required String unit,
  }) {
    final color = Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
          children: [
            const TextSpan(text: 'Stock '),
            TextSpan(
              text: stock,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: unit.trim().isEmpty ? '' : ' ${unit.trim()}'),
          ],
        ),
      ),
    );
  }
}

