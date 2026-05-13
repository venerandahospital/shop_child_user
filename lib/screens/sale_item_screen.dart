import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/item.dart';
import '../utils/barcode_utils.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'barcode_scan_screen.dart';

const _kSaleFlowScaffoldBg = Color(0xFFF4F5F7);
const _kSaleFlowAppBarBlue = Color(0xFF5181da);

class SaleItemScreen extends StatefulWidget {
  const SaleItemScreen({
    super.key,
    required this.items,
    this.selectedItem,
    required this.currencySymbol,
    this.wholesaleMode = false,
    this.initialSearchQuery,
    this.barcodeAliasesByItemId = const {},
  });

  final List<Item> items;
  final Item? selectedItem;
  final String currencySymbol;
  /// When true, list subtitles use wholesale/pack wording. Tabs still control filtering.
  final bool wholesaleMode;
  /// Prefills search (e.g. after a scan from the New sale page).
  final String? initialSearchQuery;
  final Map<int, List<String>> barcodeAliasesByItemId;

  @override
  State<SaleItemScreen> createState() => _SaleItemScreenState();
}

class _SaleItemScreenState extends State<SaleItemScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SpeechToText _speech = SpeechToText();
  late final TabController _tabController;
  /// When false (default), list rows have no leading image/letter.
  bool _showItemLeads = false;
  bool _speechReady = false;
  bool _isListening = false;

  /// Normalized sale slug: `retail`, `wholesale`, or `service`. Anything else → `retail`.
  static String _itemSaleSlug(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return 'retail';

    String? sale;
    for (final part in raw.split('|').map((p) => p.trim())) {
      if (part.isEmpty) continue;
      final lower = part.toLowerCase();
      if (lower.startsWith('sale:')) {
        final colon = part.indexOf(':');
        sale = part.substring(colon + 1).trim();
        break;
      }
    }

    if (sale == null || sale.isEmpty) {
      final hasBusiness =
          raw.toLowerCase().contains('business:') && raw.contains(':');
      if (!hasBusiness) {
        sale = raw;
      }
    }

    if (sale == null || sale.isEmpty) return 'retail';

    final slug = sale.trim().toLowerCase();
    if (slug == 'wholesale') return 'wholesale';
    if (slug == 'service') return 'service';
    if (slug == 'retail') return 'retail';
    return 'retail';
  }

  bool _itemMatchesTab(Item item, int tabIndex) {
    final slug = _itemSaleSlug(item);
    switch (tabIndex) {
      case 0:
        return slug == 'retail';
      case 1:
        return slug == 'wholesale';
      case 2:
        return slug == 'service';
      default:
        return true;
    }
  }

  String _saleCategoryLabel(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final last = parts.last;
    final normalized = last.toLowerCase().startsWith('sale:')
        ? last.substring(last.indexOf(':') + 1).trim()
        : last;
    return toTitleCaseWords(normalized);
  }

  String _unitLabel(Item item) {
    final full = (item.unit ?? '').trim();
    if (full.isNotEmpty) return toTitleCaseWords(full);
    final short = (item.unitShort ?? '').trim();
    return short;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _searchController.addListener(() => setState(() {}));
    final prefill = widget.initialSearchQuery?.trim();
    if (prefill != null && prefill.isNotEmpty) {
      _searchController.text = prefill;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // On phone, prefer camera scan first — don't open the keyboard immediately.
      if (kIsWeb) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
          setState(() {});
        }
      },
    );
  }

  List<Item> _filteredForTab(int tabIndex) {
    return widget.items.where((e) => _itemMatchesTab(e, tabIndex)).toList();
  }

  List<Item> _visibleItems(int tabIndex) {
    final tabItems = _filteredForTab(tabIndex);
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return tabItems;
    final rawQ = _searchController.text.trim();
    return tabItems.where((e) {
      if (itemBarcodeOrSkuMatchesScanned(
        e.barcode,
        e.sku,
        rawQ,
        acceptedBarcodes: widget.barcodeAliasesByItemId[e.id ?? -1] ?? const [],
      )) {
        return true;
      }
      final name = e.name.toLowerCase();
      final cat = (e.category ?? '').toLowerCase();
      final sku = (e.sku ?? '').toLowerCase();
      final barcode = (e.barcode ?? '').toLowerCase();
      return name.contains(q) ||
          cat.contains(q) ||
          sku.contains(q) ||
          barcode.contains(q);
    }).toList();
  }

  bool _rowWholesaleMode(int tabIndex) =>
      widget.wholesaleMode || tabIndex == 1;

  void _closeAndPop([Item? result]) {
    FocusScope.of(context).unfocus();
    final nav = Navigator.of(context);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;
      nav.pop(result);
    });
  }

  List<Item> _itemsMatchingBarcode(String scanned) {
    return widget.items
        .where(
          (e) => itemBarcodeOrSkuMatchesScanned(
            e.barcode,
            e.sku,
            scanned,
            acceptedBarcodes:
                widget.barcodeAliasesByItemId[e.id ?? -1] ?? const [],
          ),
        )
        .toList();
  }

  int _tabIndexForItem(Item item) {
    final slug = _itemSaleSlug(item);
    if (slug == 'wholesale') return 1;
    if (slug == 'service') return 2;
    return 0;
  }

  Future<void> _openBarcodeScanner() async {
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
    _applyScannedCode(code);
  }

  void _applyScannedCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    final matches = _itemsMatchingBarcode(trimmed);
    if (matches.length == 1) {
      final item = matches.first;
      final tab = _tabIndexForItem(item);
      if (_tabController.index != tab) {
        _tabController.animateTo(tab);
      }
      _searchController.text = trimmed;
      _closeAndPop(item);
      return;
    }
    if (matches.length > 1) {
      _searchController.text = trimmed;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Several items share this code. Choose the correct row below.',
          ),
        ),
      );
      return;
    }

    _searchController.text = trimmed;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No item with barcode "$trimmed". Add it under Items (Barcode / SKU) or check the code.',
        ),
      ),
    );
  }

  String _emptyMessageForTab(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return 'No retail items. Set sale category to Retail on the Items page.';
      case 1:
        return 'No wholesale items. Set sale category to Wholesale on the Items page.';
      case 2:
        return 'No service items. Set sale category to Service on the Items page.';
      default:
        return 'No items.';
    }
  }

  Widget _buildItemList(ThemeData theme, int tabIndex) {
    final filtered = _visibleItems(tabIndex);

    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No items yet. Add items on the Items page.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_filteredForTab(tabIndex).isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _emptyMessageForTab(tabIndex),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No items match your search.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        final selected = widget.selectedItem?.id == item.id;
        return ListTile(
          leading: _showItemLeads
              ? CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: (item.imageUrl ?? '').trim().isNotEmpty
                      ? NetworkImage(item.imageUrl!)
                      : null,
                  child: (item.imageUrl ?? '').trim().isNotEmpty
                      ? null
                      : Text(
                          item.name.isNotEmpty
                              ? item.name.substring(0, 1).toUpperCase()
                              : '?',
                        ),
                )
              : null,
          title: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: toTitleCaseWords(item.name),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_unitLabel(item).isNotEmpty)
                  TextSpan(
                    text: ' - ${_unitLabel(item)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (_saleCategoryLabel(item).isNotEmpty)
                  TextSpan(
                    text: ' - ${_saleCategoryLabel(item)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          subtitle: Text(
            _rowWholesaleMode(tabIndex)
                ? 'Stock: ${formatDisplayNumber(item.stockQty.floorToDouble())} ${(item.unitShort ?? item.unit ?? 'carton').trim()}\nSell: ${widget.currencySymbol}${formatMoney(item.sellingPrice)} / pack  •  Cost: ${widget.currencySymbol}${formatMoney(item.costPrice)} / pack'
                : 'Stock: ${formatDisplayNumber(item.stockQty)} ${item.unit ?? ''}\nSell: ${widget.currencySymbol}${formatMoney(item.sellingPrice)}  •  Cost: ${widget.currencySymbol}${formatMoney(item.costPrice)}',
            style: theme.textTheme.bodySmall,
          ),
          selected: selected,
          onTap: () => _closeAndPop(item),
        );
      },
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: theme.dividerColor.withValues(alpha: 0.45),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeAndPop();
      },
      child: Scaffold(
        backgroundColor: _kSaleFlowScaffoldBg,
        appBar: AppBar(
          backgroundColor: _kSaleFlowAppBarBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const SectionPageTitle(pageTitle: 'Select item'),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan barcode',
              onPressed: _openBarcodeScanner,
            ),
            IconButton(
              icon: Icon(
                _showItemLeads
                    ? Icons.remove_red_eye
                    : Icons.remove_red_eye_outlined,
              ),
              tooltip: _showItemLeads
                  ? 'Hide item pictures'
                  : 'Show item pictures',
              onPressed: () {
                setState(() => _showItemLeads = !_showItemLeads);
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Retail'),
              Tab(text: 'Wholesale'),
              Tab(text: 'Service'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!kIsWeb) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: FilledButton.icon(
                    onPressed: _openBarcodeScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 26),
                    label: const Text('Scan barcode with phone camera'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    'Fastest at the counter: point at the product barcode. '
                    'Or search the list below.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: kIsWeb,
                  decoration: InputDecoration(
                    labelText: 'Search name or barcode',
                    hintText: kIsWeb
                        ? 'Type to filter'
                        : 'Optional: type to search the list',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: _isListening ? 'Stop voice search' : 'Voice search',
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      onPressed: _toggleVoiceSearch,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_isListening)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildItemList(theme, 0),
                    _buildItemList(theme, 1),
                    _buildItemList(theme, 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
