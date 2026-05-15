import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/cart_draft.dart';
import '../models/item.dart';
import '../models/client.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/auth_service.dart';
import '../services/mother_data_cache.dart';
import '../services/remote_sync_service.dart';
import '../utils/barcode_utils.dart';
import '../utils/meter_fixed_stock_items.dart';
import '../utils/special_item_sale_dialog.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'sales_history_screen.dart';
import 'sale_quantity_screen.dart';
import 'sale_client_screen.dart';
import 'sale_item_screen.dart';
import 'sale_amount_received_screen.dart';
import 'sale_overall_discount_screen.dart';
import 'sale_account_payment_screen.dart';
import 'barcode_scan_screen.dart';
import 'dashboard_screen.dart';
import 'cart_drafts_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _CartEntry {
  final Item item;
  final double quantity;
  final double productDiscount;

  const _CartEntry({
    required this.item,
    required this.quantity,
    this.productDiscount = 0,
  });
}

class _SaleReceiptLine {
  final String itemName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double productDiscount;

  const _SaleReceiptLine({
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.productDiscount,
  });

  double get subtotal => quantity * unitPrice;
  double get discountApplied => productDiscount > subtotal ? subtotal : productDiscount;
  double get netTotal {
    final net = subtotal - discountApplied;
    return net < 0 ? 0 : net;
  }
}

enum _PaymentMode { all, partial, zeroPaid }
enum _SalePaymentMethod { cash, mobileMoney, account }

String _salePaymentMethodWireValue(_SalePaymentMethod method) {
  switch (method) {
    case _SalePaymentMethod.cash:
      return 'cash';
    case _SalePaymentMethod.mobileMoney:
      return 'mobile_money';
    case _SalePaymentMethod.account:
      return 'account';
  }
}

class _SalesScreenState extends State<SalesScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;

  List<Item> _items = [];
  Map<int, List<String>> _itemBarcodeAliases = const {};
  Item? _selectedItem;
  List<Client> _clients = [];
  Client? _selectedClient;
  final TextEditingController _qtyController = TextEditingController(text: '0');
  final List<_CartEntry> _cart = [];
  bool _saving = false;
  String _currencySymbol = 'USh';
  _PaymentMode _paymentMode = _PaymentMode.all;
  _SalePaymentMethod _paymentMethod = _SalePaymentMethod.cash;
  final TextEditingController _amountReceivedController =
      TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  bool _discountRadioSelected = false;
  bool _refreshing = false;

  static const Color _pageBackground = Color(0xFFF4F5F7);
  static const Color _brandBlue = Color(0xFF5181da);

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadItems();
    _loadClients();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  void _showDraftSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  bool _sameLine(_CartEntry line, Item item) {
    return line.item.id == item.id;
  }

  bool _isServiceSaleItem(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return false;
    String? sale;
    for (final part in raw.split('|').map((p) => p.trim())) {
      if (part.toLowerCase().startsWith('sale:')) {
        sale = part.substring(part.indexOf(':') + 1).trim().toLowerCase();
        break;
      }
    }
    sale ??= raw.toLowerCase();
    return sale == 'service';
  }

  bool _isMeterFixedStockItem(Item item) =>
      isMeterSoldFixedStockItemName(item.name);

  /// Service lines, or special items with stock 1: any sale qty without reducing stock.
  bool _lineIgnoresStockOnHand(Item item) {
    if (_isServiceSaleItem(item)) return true;
    if (_isMeterFixedStockItem(item) && item.stockQty > 0) return true;
    return false;
  }

  String _saleCategoryLabel(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return '';
    for (final part in raw.split('|').map((p) => p.trim())) {
      if (part.toLowerCase().startsWith('sale:')) {
        return toTitleCaseWords(part.substring(part.indexOf(':') + 1).trim());
      }
    }
    return toTitleCaseWords(raw);
  }

  Item? _itemById(int? id) {
    if (id == null) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Latest item row for [item] (by id) after [_items] has been refreshed.
  Item? _freshItem(Item? item) => item == null ? null : (_itemById(item.id) ?? item);

  void _rebindCartToFreshItems() {
    if (_cart.isEmpty) return;
    for (var i = 0; i < _cart.length; i++) {
      final e = _cart[i];
      final fresh = _freshItem(e.item) ?? e.item;
      if (!identical(fresh, e.item)) {
        _cart[i] = _CartEntry(
          item: fresh,
          quantity: e.quantity,
          productDiscount: e.productDiscount,
        );
      }
    }
  }

  /// Wi‑Fi: always pull from mother before pick-list / barcode / quantity.
  Future<bool> _refreshItemsFromMother({bool showError = true}) async {
    final isRemote = await _auth.isRemoteUser();
    if (!isRemote) {
      await _loadItems(clearSelection: false);
      return true;
    }
    final (ok, message, items) =
        await RemoteSyncService.instance.pullItemsFromMother();
    if (!mounted) return false;
    if (!ok) {
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return false;
    }
    final aliases = MotherDataCache.instance.getItemBarcodeAliasesMap();
    setState(() {
      _items = items;
      _itemBarcodeAliases = aliases;
      _selectedItem = _freshItem(_selectedItem);
    });
    return true;
  }

  Future<void> _loadItems({bool clearSelection = true}) async {
    final isRemote = await _auth.isRemoteUser();
    final items = isRemote
        ? await RemoteSyncService.instance.fetchItems()
        : await _db.getItems();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final Map<int, List<String>> aliases = isRemote
        ? MotherDataCache.instance.getItemBarcodeAliasesMap()
        : await _db.getItemBarcodesMap(
            itemIds: items.map((e) => e.id).whereType<int>(),
          );
    if (!mounted) return;
    setState(() {
      _items = items;
      _itemBarcodeAliases = aliases;
      if (clearSelection) {
        _selectedItem = null;
      } else {
        _selectedItem = _freshItem(_selectedItem);
      }
    });
  }

  Future<void> _loadClients() async {
    final clients = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchClients()
        : await _db.getClients();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _selectedClient = _clients.any((c) => c.id == _selectedClient?.id)
          ? _selectedClient
          : null;
    });
  }

  Future<void> _refreshSaleData() async {
    setState(() => _refreshing = true);
    try {
      await _auth.connectViaSavedUrls() ??
          (await _auth.testConnectionWithFallback()).$3;
      await Future.wait([_loadItems(), _loadClients()]);
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  bool _hasUnsavedSaleProgress() {
    if (_cart.isNotEmpty) return true;
    if (_selectedClient != null) return true;
    if (_amountReceivedController.text.trim().isNotEmpty) return true;
    if (_discountRadioSelected) return true;
    if (_selectedItem != null && _enteredQty > 0) return true;
    return false;
  }

  Map<String, dynamic> _buildDraftPayloadMap() {
    return {
      'v': 1,
      'lines': _cart
          .where((e) => e.item.id != null)
          .map(
            (e) => {
              'itemId': e.item.id,
              'quantity': e.quantity,
              'productDiscount': e.productDiscount,
            },
          )
          .toList(),
      'clientId': _selectedClient?.id,
      'paymentMode': _paymentMode.name,
      'paymentMethod': _paymentMethod.name,
      'amountReceived': _amountReceivedController.text,
      'discountText': _discountController.text,
      'discountRadioSelected': _discountRadioSelected,
    };
  }

  String _defaultDraftTitle() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    final h = n.hour.toString().padLeft(2, '0');
    final min = n.minute.toString().padLeft(2, '0');
    return 'Draft $m/$d $h:$min';
  }

  Future<String?> _openSaveDraftPage(String initialTitle) async {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _SaveDraftNameScreen(initialTitle: initialTitle),
      ),
    );
  }

  Future<void> _saveCartDraft() async {
    if (_cart.isEmpty) {
      _showDraftSnack('Cart is empty - add items before saving a draft.');
      return;
    }
    final defaultTitle = _defaultDraftTitle();
    final name = await _openSaveDraftPage(defaultTitle);
    if (name == null || !mounted) return;
    final title = name.isEmpty ? defaultTitle : name;
    final payloadMap = _buildDraftPayloadMap();
    final lines = payloadMap['lines'] as List? ?? const [];
    if (lines.isEmpty) {
      _showDraftSnack(
        'This cart cannot be saved as draft because item IDs are missing.',
      );
      return;
    }
    final json = jsonEncode(payloadMap);
    try {
      await _db.insertCartDraft(title: title, payloadJson: json);
      if (!mounted) return;
      _showDraftSnack('Draft saved: $title');
    } catch (e) {
      if (!mounted) return;
      _showDraftSnack('Could not save draft: $e');
    }
  }

  Future<void> _openCartDrafts() async {
    final draft = await Navigator.push<CartDraft>(
      context,
      MaterialPageRoute(builder: (_) => const CartDraftsScreen()),
    );
    if (draft == null || !mounted) return;
    if (_hasUnsavedSaleProgress()) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace current sale?'),
          content: const Text(
            'You have items or payment details on this screen. '
            'Loading a draft will replace them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Load draft'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await _applyCartDraft(draft);
  }

  Future<void> _applyCartDraft(CartDraft draft) async {
    late final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(draft.payloadJson);
      if (decoded is! Map) {
        throw FormatException('not a map');
      }
      payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This draft is damaged and cannot be loaded.'),
          ),
        );
      }
      return;
    }
    final lines = payload['lines'] as List?;
    if (lines == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid draft payload.')),
        );
      }
      return;
    }

    final newCart = <_CartEntry>[];
    final missingIds = <int>[];
    for (final raw in lines) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final itemId = map['itemId'] as int?;
      if (itemId == null) continue;
      Item? found;
      for (final i in _items) {
        if (i.id == itemId) {
          found = i;
          break;
        }
      }
      if (found == null) {
        missingIds.add(itemId);
        continue;
      }
      final qty = (map['quantity'] as num?)?.toDouble() ?? 0;
      final disc = (map['productDiscount'] as num?)?.toDouble() ?? 0;
      if (qty <= 0) continue;
      newCart.add(
        _CartEntry(item: found, quantity: qty, productDiscount: disc),
      );
    }

    final clientId = payload['clientId'] as int?;
    Client? client;
    if (clientId != null) {
      for (final c in _clients) {
        if (c.id == clientId) {
          client = c;
          break;
        }
      }
    }

    final pm = payload['paymentMode'] as String?;
    final methodRaw = payload['paymentMethod'] as String?;
    var paymentMethod = _SalePaymentMethod.cash;
    if (methodRaw == _SalePaymentMethod.mobileMoney.name) {
      paymentMethod = _SalePaymentMethod.mobileMoney;
    } else if (methodRaw == _SalePaymentMethod.account.name) {
      paymentMethod = _SalePaymentMethod.account;
    }

    var mode = _PaymentMode.all;
    if (pm == _PaymentMode.partial.name) {
      mode = _PaymentMode.partial;
    } else if (pm == _PaymentMode.zeroPaid.name) {
      mode = _PaymentMode.zeroPaid;
    }

    final amountReceived = payload['amountReceived'] as String? ?? '';
    final discountText = payload['discountText'] as String? ?? '';
    final discRadio = payload['discountRadioSelected'] as bool? ?? false;

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _cart.addAll(newCart);
      _selectedClient = client;
      _paymentMode = mode;
      _paymentMethod = paymentMethod;
      _amountReceivedController.text = amountReceived;
      _discountController.text = discountText;
      _discountRadioSelected = discRadio;
      _selectedItem = null;
      _qtyController.text = '0';
    });

    if (!mounted) return;
    if (newCart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No lines could be restored from this draft.'),
        ),
      );
    } else {
      if (missingIds.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${missingIds.length} item(s) skipped (no longer in catalog).',
            ),
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded draft: ${draft.title}')),
      );
    }
    if (clientId != null && client == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved client is no longer in the list.'),
        ),
      );
    }
  }

  InputDecoration _selectorFieldDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: const Icon(Icons.arrow_drop_down),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  double get _cartTotal {
    double total = 0;
    for (final entry in _cart) {
      final gross = entry.item.sellingPrice * entry.quantity;
      final discount = entry.productDiscount > gross ? gross : entry.productDiscount;
      total += gross - discount;
    }
    return total;
  }

  double get _enteredQty {
    return double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0;
  }

  double get _enteredDiscount {
    if (!_discountRadioSelected) return 0;
    return double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0;
  }

  double get _effectiveDiscount {
    final subtotal = _cartTotal;
    final discount = _enteredDiscount;
    if (discount <= 0) return 0;
    return discount > subtotal ? subtotal : discount;
  }

  double get _liveSubtotal {
    if (_selectedItem == null) return _cartTotal;
    final qty = _enteredQty;
    if (qty <= 0) return _cartTotal;
    return _cartTotal + (_selectedItem!.sellingPrice * qty);
  }

  double get _liveTotal {
    final net = _liveSubtotal - _effectiveDiscount;
    return net < 0 ? 0 : net;
  }

  String _fmtCompactNumber(double value) {
    return formatDisplayNumber(value);
  }

  String _fmtMoney(double value) {
    return formatMoney(value);
  }

  bool get _isAllReceived => _paymentMode == _PaymentMode.all;
  bool get _needsClient => _paymentMode != _PaymentMode.all;

  Future<void> _openOverallDiscountScreen() async {
    final value = await Navigator.of(context).push<double?>(
      MaterialPageRoute(
        builder: (_) => SaleOverallDiscountScreen(
          cartSubtotal: _cartTotal,
          initialDiscountText: _discountController.text,
          currencySymbol: _currencySymbol,
        ),
      ),
    );
    if (!mounted || value == null) return;
    setState(() {
      _discountRadioSelected = true;
      _discountController.text = _fmtCompactNumber(value);
      if (_isAllReceived) {
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      }
    });
  }

  void _setPaymentMode(_PaymentMode mode) {
    if (_paymentMode == mode) return;
    if (mode == _PaymentMode.all) {
      setState(() {
        _paymentMode = _PaymentMode.all;
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      });
      return;
    }
    if (mode == _PaymentMode.partial) {
      setState(() => _paymentMode = _PaymentMode.partial);
      if (_selectedClient == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openClientPage(openAmountAfterSelect: true);
        });
      }
      return;
    }
    setState(() {
      _paymentMode = _PaymentMode.zeroPaid;
      _amountReceivedController.text = '0';
    });
    if (_selectedClient == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openClientPage(
            openAmountAfterSelect: false,
            setZeroAfterSelect: true,
          );
        }
      });
    }
  }

  Future<void> _setSalePaymentMethod(_SalePaymentMethod method) async {
    if (_paymentMethod == method) return;
    setState(() => _paymentMethod = method);
    if (method != _SalePaymentMethod.account) return;
    await _openAccountPaymentPageAndApply();
  }

  Future<double> _fetchClientAccountBalance(int clientId) async {
    final isRemote = await _auth.isRemoteUser();
    if (isRemote) {
      return (await _auth.fetchRemoteClientAccountBalance(clientId)) ?? 0;
    }
    return _db.getClientAccountBalance(clientId);
  }

  Future<void> _openAccountPaymentPageAndApply() async {
    if (_clients.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No clients available. Add a client first.')),
      );
      return;
    }
    if (_selectedClient == null) {
      await _openClientPage(openAmountAfterSelect: false);
      if (!mounted || _selectedClient == null) return;
    }
    final client = _selectedClient;
    if (client?.id == null) return;
    final balance = await _fetchClientAccountBalance(client!.id!);
    if (!mounted) return;
    final payable = await Navigator.of(context).push<double>(
      MaterialPageRoute(
        builder: (_) => SaleAccountPaymentScreen(
          clientName: client.name,
          currencySymbol: _currencySymbol,
          totalAmount: _liveTotal,
          availableBalance: balance,
        ),
      ),
    );
    if (!mounted || payable == null) return;
    final safePay = payable < 0 ? 0.0 : payable;
    setState(() {
      _paymentMethod = _SalePaymentMethod.account;
      if (safePay >= _liveTotal) {
        _paymentMode = _PaymentMode.all;
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      } else if (safePay > 0) {
        _paymentMode = _PaymentMode.partial;
        _amountReceivedController.text = _fmtCompactNumber(safePay);
      } else {
        _paymentMode = _PaymentMode.zeroPaid;
        _amountReceivedController.text = '0';
      }
    });
  }

  Future<void> _addToCart({double? forcedQty, double? forcedProductDiscount}) async {
    if (_selectedItem == null) return;
    if (await _auth.isRemoteUser()) {
      await _refreshItemsFromMother(showError: false);
    }
    if (!mounted) return;
    final selectedItem = _freshItem(_selectedItem);
    if (selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item not found. Pull to refresh items.')),
      );
      return;
    }
    if (_selectedItem!.id != selectedItem.id ||
        _selectedItem!.stockQty != selectedItem.stockQty) {
      setState(() => _selectedItem = selectedItem);
    }
    if (_isMeterFixedStockItem(selectedItem) && selectedItem.stockQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toTitleCaseWords(selectedItem.name)} is out of stock. Receive a roll first.',
          ),
        ),
      );
      return;
    }
    final skipStockCap = _lineIgnoresStockOnHand(selectedItem);

    final qty =
        forcedQty ?? (double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0);
    final productDiscount = forcedProductDiscount ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid quantity')));
      return;
    }
    if (!skipStockCap) {
      // Ensure we don't exceed available stock for this item
      final currentQtyForItem = _cart
          .where((e) => e.item.id == selectedItem.id)
          .fold<double>(0, (sum, e) => sum + e.quantity);
      final remainingStock = selectedItem.stockQty - currentQtyForItem;
      final maxAllowed = remainingStock;

      if (qty > maxAllowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Not enough stock. Available: ${_fmtCompactNumber(maxAllowed)}',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      final index = _cart.indexWhere((e) => _sameLine(e, selectedItem));
      final entry = index >= 0
          ? _CartEntry(
              item: _cart[index].item,
              quantity: _cart[index].quantity + qty,
              productDiscount: _cart[index].productDiscount + productDiscount,
            )
          : _CartEntry(
              item: selectedItem,
              quantity: qty,
              productDiscount: productDiscount,
            );
      if (index >= 0) {
        _cart.removeAt(index);
      }
      _cart.insert(0, entry);
      _qtyController.text = '0';
      if (_isAllReceived) {
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      }
    });
  }

  Future<void> _applySpecialLineOutcomeNow({
    required int itemId,
    required bool stillAvailable,
    required double metersSold,
    required bool isRemote,
  }) async {
    if (isRemote) {
      final (ok, message) =
          await RemoteSyncService.instance.pushSpecialSaleOutcomeToMother(
        itemId: itemId,
        stillAvailable: stillAvailable,
        metersSold: metersSold,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } else {
      await _db.applySpecialItemSaleOutcome(
        itemId: itemId,
        stillAvailable: stillAvailable,
        metersSold: metersSold,
      );
    }
    if (mounted) {
      await _refreshItemsFromMother(showError: false);
      setState(_rebindCartToFreshItems);
    }
  }

  Future<void> _confirmSpecialItemsAfterSale({
    required List<_CartEntry> specialLines,
    required bool isRemote,
  }) async {
    if (specialLines.isEmpty) return;

    for (final entry in specialLines) {
      final itemId = entry.item.id;
      if (itemId == null) continue;
      if (!mounted) return;
      final stillAvailable = await showSpecialItemAvailabilityDialog(
        context,
        itemName: entry.item.name,
      );
      if (!mounted) return;

      await _applySpecialLineOutcomeNow(
        itemId: itemId,
        stillAvailable: stillAvailable,
        metersSold: entry.quantity,
        isRemote: isRemote,
      );
    }
  }

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to the sale')),
      );
      return;
    }

    if (await _auth.isRemoteUser()) {
      if (!await _refreshItemsFromMother()) return;
      if (!mounted) return;
      setState(_rebindCartToFreshItems);
    }

    final specialLines =
        _cart.where((e) => _isMeterFixedStockItem(e.item)).toList();

    // Validate stock before saving
    for (final entry in _cart) {
      if (entry.quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid quantity for ${toTitleCaseWords(entry.item.name)}')),
        );
        return;
      }
      if (_isMeterFixedStockItem(entry.item) && entry.item.stockQty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${toTitleCaseWords(entry.item.name)} is out of stock. Receive stock first.',
            ),
          ),
        );
        return;
      }
      if (!_lineIgnoresStockOnHand(entry.item) && entry.quantity > entry.item.stockQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Not enough stock for ${toTitleCaseWords(entry.item.name)}. Available: ${entry.item.stockQty}',
            ),
          ),
        );
        return;
      }
    }

    final subtotal = _cartTotal;
    final discount = _enteredDiscount;
    if (discount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discount cannot be negative')),
      );
      return;
    }
    if (discount > subtotal) {
      _discountController.text = _fmtCompactNumber(subtotal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Discount is too high. Max discount is $_currencySymbol${_fmtMoney(subtotal)}.',
          ),
        ),
      );
      return;
    }
    final totalAmount = subtotal - discount;
    final parsedAmount =
        double.tryParse(_amountReceivedController.text.replaceAll(',', '.')) ??
        0;
    double amountReceived = _paymentMode == _PaymentMode.all
        ? totalAmount
        : _paymentMode == _PaymentMode.zeroPaid
        ? 0.0
        : parsedAmount;
    if (_paymentMethod == _SalePaymentMethod.account) {
      if (_clients.isEmpty || _selectedClient == null) {
        await _openClientPage(openAmountAfterSelect: false);
        if (!mounted) return;
      }
      if (_selectedClient?.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a client before paying with account.'),
          ),
        );
        return;
      }
      final balanceAmount = await _fetchClientAccountBalance(_selectedClient!.id!);
      if (!mounted) return;
      final payable = balanceAmount <= 0
          ? 0.0
          : (balanceAmount >= totalAmount ? totalAmount : balanceAmount);
      amountReceived = payable;
      setState(() {
        if (payable >= totalAmount) {
          _paymentMode = _PaymentMode.all;
          _amountReceivedController.text = _fmtCompactNumber(totalAmount);
        } else if (payable > 0) {
          _paymentMode = _PaymentMode.partial;
          _amountReceivedController.text = _fmtCompactNumber(payable);
        } else {
          _paymentMode = _PaymentMode.zeroPaid;
          _amountReceivedController.text = '0';
        }
      });
    }

    if (_paymentMode == _PaymentMode.partial && amountReceived <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter paid amount')));
      return;
    }
    if (amountReceived > totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paid amount cannot be more than total'),
        ),
      );
      return;
    }
    final balance = totalAmount - amountReceived;
    if (balance > 0) {
      if (_clients.isEmpty || _selectedClient == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'For partial payment, please select a client for the debt',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    final storeId = _cart.first.item.storeId;
    final clientForSale = (_paymentMethod == _SalePaymentMethod.account || balance > 0)
        ? _selectedClient
        : null;
    final sale = Sale(
      storeId: storeId,
      totalAmount: totalAmount,
      overallDiscount: _effectiveDiscount,
      amountReceived: amountReceived,
      balance: balance,
      customerName: clientForSale?.name,
      customerPhone: clientForSale?.phone,
      customerAddress: clientForSale?.address,
      paymentMethod: _salePaymentMethodWireValue(_paymentMethod),
    );

    final saleItems = _cart
        .map(
          (entry) => SaleItem(
            itemId: entry.item.id!,
            quantity: entry.quantity,
            unitPrice: entry.item.sellingPrice,
            productDiscount: entry.productDiscount,
          ),
        )
        .toList();

    final remoteSaleItems = saleItems
        .map(
          (e) => <String, dynamic>{
            'itemId': e.itemId,
            'quantity': e.quantity,
            'unitPrice': e.unitPrice,
            'productDiscount': e.productDiscount,
            'lineTotal': e.lineTotal,
          },
        )
        .toList();

    final isRemote = await _auth.isRemoteUser();
    late final int saleId;
    if (isRemote) {
      if (_paymentMethod == _SalePaymentMethod.account &&
          amountReceived > 0 &&
          clientForSale?.id != null) {
        final tx = await _auth.postRemoteClientAccountTransaction(
          clientId: clientForSale!.id!,
          amount: -amountReceived,
          transactionType: 'sale_payment',
          note: 'Sale payment',
        );
        if (tx['success'] != true) {
          if (!mounted) return;
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((tx['message'] ?? 'Account payment failed').toString())),
          );
          return;
        }
      }
      final remote = await _auth.createRemoteSale({
        'storeId': sale.storeId,
        'totalAmount': sale.totalAmount,
        'overallDiscount': sale.overallDiscount,
        'amountReceived': sale.amountReceived,
        'balance': sale.balance,
        'customerName': sale.customerName,
        'customerPhone': sale.customerPhone,
        'customerAddress': sale.customerAddress,
        'paymentMethod': _salePaymentMethodWireValue(_paymentMethod),
        'items': remoteSaleItems,
      });
      if (remote['success'] != true) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (remote['message'] ?? 'Failed to sync sale').toString(),
            ),
          ),
        );
        return;
      }
      final rawId = remote['saleId'];
      saleId = rawId is int ? rawId : (int.tryParse('$rawId') ?? 0);
    } else {
      if (_paymentMethod == _SalePaymentMethod.account &&
          amountReceived > 0 &&
          clientForSale?.id != null) {
        await _db.recordClientAccountTransaction(
          clientId: clientForSale!.id!,
          storeId: clientForSale.storeId,
          transactionType: 'sale_payment',
          amount: -amountReceived,
          note: 'Sale payment',
        );
      }
      saleId = await _db.createSale(sale, saleItems);
    }

    await _confirmSpecialItemsAfterSale(
      specialLines: specialLines,
      isRemote: isRemote,
    );
    if (!mounted) return;

    if (isRemote) {
      await RemoteSyncService.instance.fetchItems();
    } else {
      await _loadItems(clearSelection: false);
    }

    final receiptLines = _cart
        .map(
          (e) => _SaleReceiptLine(
            itemName: toTitleCaseWords(e.item.name),
            unit: (e.item.unitShort ?? e.item.unit ?? '').trim(),
            quantity: e.quantity,
            unitPrice: e.item.sellingPrice,
            productDiscount: e.productDiscount,
          ),
        )
        .toList();

    if (!mounted) return;
    setState(() {
      _saving = false;
      _cart.clear();
      _qtyController.text = '0';
      _discountController.clear();
      _amountReceivedController.clear();
      _paymentMode = _PaymentMode.all;
      _paymentMethod = _SalePaymentMethod.cash;
    });

    await _showSaleReceiptPopup(
      saleId: saleId,
      totalAmount: totalAmount,
      overallDiscount: _effectiveDiscount,
      amountReceived: amountReceived,
      balance: balance,
      lines: receiptLines,
    );
  }

  Future<void> _showSaleReceiptPopup({
    required int saleId,
    required double totalAmount,
    required double overallDiscount,
    required double amountReceived,
    required double balance,
    required List<_SaleReceiptLine> lines,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _SaleReceiptDialog(
        saleId: saleId,
        currencySymbol: _currencySymbol,
        totalAmount: totalAmount,
        overallDiscount: overallDiscount,
        amountReceived: amountReceived,
        balance: balance,
        lines: lines,
        onProceedToSalesHistory: _navigateToSalesHistoryAfterSale,
      ),
    );
  }

  void _navigateToSalesHistoryAfterSale() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
    );
  }

  List<Item> _itemsMatchingBarcode(String scanned) {
    return itemsMatchingBarcodeScan<Item>(
      _items,
      scanned,
      (e) => barcodeScanMatchKindForItem(
        barcode: e.barcode,
        sku: e.sku,
        scanned: scanned,
        acceptedBarcodes: _itemBarcodeAliases[e.id ?? -1] ?? const [],
      ),
    );
  }

  Future<void> _openBarcodeScannerFromSalePage() async {
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
    await _applyBarcodeToSale(code);
  }

  Future<void> _applyBarcodeToSale(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    if (!await _refreshItemsFromMother()) return;
    if (!mounted) return;
    final matches = _itemsMatchingBarcode(trimmed);
    final usedPartialMatch = matches.isNotEmpty &&
        barcodeScanMatchKindForItem(
              barcode: matches.first.barcode,
              sku: matches.first.sku,
              scanned: trimmed,
              acceptedBarcodes:
                  _itemBarcodeAliases[matches.first.id ?? -1] ?? const [],
            ) ==
            BarcodeScanMatchKind.fuzzy;
    if (matches.length == 1) {
      final item = _freshItem(matches.first) ?? matches.first;
      if (_isMeterFixedStockItem(item) && item.stockQty <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${toTitleCaseWords(item.name)} is out of stock. Receive a roll on the mother device first.',
            ),
          ),
        );
        return;
      }
      if (usedPartialMatch && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Matched from a partial barcode scan — check the item is correct.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        _selectedItem = item;
        if (_isAllReceived) {
          _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
        }
      });
      if (_isServiceSaleItem(item)) {
        await _addToCart(forcedQty: 1);
        return;
      }
      await _openQuantityPage();
      return;
    }
    if (matches.length > 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Several items share this code. Choose the correct one in the list.',
          ),
        ),
      );
      await _openItemPage(initialSearchQuery: trimmed);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No item with barcode "$trimmed". Add it under Items or pick from the list.',
        ),
      ),
    );
    await _openItemPage(initialSearchQuery: trimmed);
  }

  Future<void> _openItemPage({String? initialSearchQuery}) async {
    if (!await _refreshItemsFromMother()) return;
    if (!mounted || _items.isEmpty) return;
    final result = await Navigator.of(context).push<Item>(
      MaterialPageRoute<Item>(
        builder: (context) => SaleItemScreen(
          items: _items,
          barcodeAliasesByItemId: _itemBarcodeAliases,
          selectedItem: _freshItem(_selectedItem),
          currencySymbol: _currencySymbol,
          initialSearchQuery: initialSearchQuery,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final picked = _freshItem(result) ?? result;
    if (_isMeterFixedStockItem(picked) && picked.stockQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toTitleCaseWords(picked.name)} is out of stock. Receive stock on the mother device first.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _selectedItem = picked;
      if (_isAllReceived) {
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      }
    });
    if (_isServiceSaleItem(result)) {
      await _addToCart(forcedQty: 1);
      return;
    }
    await _openQuantityPage();
  }

  Future<void> _openAmountReceivedPage() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => SaleAmountReceivedScreen(
          totalAmount: _liveTotal,
          initialAmount: _amountReceivedController.text,
          currencySymbol: _currencySymbol,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _amountReceivedController.text = result);
  }

  Future<void> _openClientPage({
    bool openAmountAfterSelect = true,
    bool setZeroAfterSelect = false,
  }) async {
    final result = await Navigator.of(context).push<Client>(
      MaterialPageRoute<Client>(
        builder: (context) => SaleClientScreen(
          clients: _clients,
          selectedClient: _selectedClient,
        ),
      ),
    );
    if (!mounted) return;
    await _loadClients();
    if (result == null) return;
    setState(() {
      _selectedClient = result;
      if (setZeroAfterSelect) {
        _amountReceivedController.text = '0';
      }
    });
    if (openAmountAfterSelect) {
      await _openAmountReceivedPage();
    }
  }

  Future<void> _openQuantityPage() async {
    if (_selectedItem == null) return;
    if (!await _refreshItemsFromMother()) return;
    if (!mounted) return;
    final item = _freshItem(_selectedItem);
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item no longer on mother. Refresh and try again.')),
      );
      setState(() => _selectedItem = null);
      return;
    }
    if (_isMeterFixedStockItem(item) && item.stockQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toTitleCaseWords(item.name)} is out of stock. Receive stock on the mother device first.',
          ),
        ),
      );
      setState(() => _selectedItem = item);
      return;
    }
    setState(() => _selectedItem = item);
    if (_isServiceSaleItem(item)) {
      await _addToCart(forcedQty: 1);
      return;
    }
    final currentQty = _cart
        .where((e) => e.item.id == item.id)
        .fold<double>(0, (sum, e) => sum + e.quantity);
    final maxAvailable = _lineIgnoresStockOnHand(item)
        ? 1e12
        : (item.stockQty - currentQty);
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        builder: (context) => SaleQuantityScreen(
          item: item,
          cartTotal: _cartTotal,
          maxAvailable: maxAvailable,
          initialQuantity: _qtyController.text,
          initialProductDiscount: '',
          currencySymbol: _currencySymbol,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final qtyText = result['quantity'] ?? '';
    final productDiscount =
        double.tryParse((result['productDiscount'] ?? '0').replaceAll(',', '.')) ?? 0;
    setState(() {
      _qtyController.text = qtyText;
      if (_isAllReceived) {
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      }
    });
    await _addToCart(forcedQty: double.tryParse(qtyText.replaceAll(',', '.')), forcedProductDiscount: productDiscount);
  }

  Future<void> _editCartEntry(int index) async {
    if (await _auth.isRemoteUser()) {
      if (!await _refreshItemsFromMother()) return;
      if (!mounted) return;
      setState(_rebindCartToFreshItems);
    }
    final entry = _cart[index];
    final item = _freshItem(entry.item) ?? entry.item;
    if (_isServiceSaleItem(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service quantity is fixed to 1 per add.')),
      );
      return;
    }
    final grossLineTotal = item.sellingPrice * entry.quantity;
    final lineTotal =
        grossLineTotal - (entry.productDiscount > grossLineTotal ? grossLineTotal : entry.productDiscount);
    final baseCartTotal = _cartTotal - lineTotal;

    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        builder: (context) => SaleQuantityScreen(
          item: item,
          cartTotal: baseCartTotal,
          maxAvailable: _lineIgnoresStockOnHand(item)
              ? 1e12
              : item.stockQty,
          initialQuantity: _fmtCompactNumber(entry.quantity),
          initialProductDiscount:
              entry.productDiscount > 0 ? _fmtCompactNumber(entry.productDiscount) : '',
          currencySymbol: _currencySymbol,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final newQty = double.tryParse((result['quantity'] ?? '').replaceAll(',', '.')) ?? -1;
    final newProductDiscount =
        double.tryParse((result['productDiscount'] ?? '0').replaceAll(',', '.')) ?? 0;
    if (newQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }
    final stockCap =
        _lineIgnoresStockOnHand(item) ? 1e12 : item.stockQty;
    if (newQty > stockCap) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough stock. Available: ${_fmtCompactNumber(stockCap)}',
          ),
        ),
      );
      return;
    }

    setState(() {
      _cart[index] = _CartEntry(
        item: item,
        quantity: newQty,
        productDiscount: newProductDiscount,
      );
      if (_isAllReceived) {
        _amountReceivedController.text = _fmtCompactNumber(_liveTotal);
      }
    });
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _qtyController.dispose();
    _amountReceivedController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
          return;
        }
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      },
      child: Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: _brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const SectionPageTitle(pageTitle: 'New sale'),
          actions: [
            IconButton(
              tooltip: 'Save cart as draft',
              onPressed: _saving ? null : _saveCartDraft,
              icon: const Icon(Icons.save_as_outlined),
            ),
            IconButton(
              tooltip: 'Open saved drafts',
              onPressed: _openCartDrafts,
              icon: const Icon(Icons.folder_open_outlined),
            ),
            IconButton(
              tooltip: 'Refresh items & clients',
              onPressed: _refreshing ? null : _refreshSaleData,
              icon: _refreshing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Padding(
        padding: EdgeInsets.only(bottom: viewInsets > 0 ? viewInsets + 16 : 16),
        child: _items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 36,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No items yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add items on the Items page first,\n'
                            'then tap refresh above.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      if (!kIsWeb) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _items.isEmpty
                                      ? null
                                      : _openBarcodeScannerFromSalePage,
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 20,
                                  ),
                                  label: const Text('Scan barcode'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 6,
                                    ),
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _items.isEmpty
                                      ? null
                                      : () => _openItemPage(),
                                  icon: const Icon(Icons.list, size: 20),
                                  label: const Text('Pick from list'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 6,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: OutlinedButton.icon(
                            onPressed:
                                _items.isEmpty ? null : () => _openItemPage(),
                            icon: const Icon(Icons.list),
                            label: const Text('Choose item'),
                          ),
                        ),
                      ],
                      if (_needsClient) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Client',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 44,
                          child: InkWell(
                            onTap: () => _openClientPage(
                              openAmountAfterSelect:
                                  _paymentMode == _PaymentMode.partial,
                              setZeroAfterSelect:
                                  _paymentMode == _PaymentMode.zeroPaid,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              isFocused: false,
                              decoration:
                                  _selectorFieldDecoration('Select client'),
                              child: Text(
                                _selectedClient != null
                                    ? _selectedClient!.name
                                    : (_clients.isEmpty
                                        ? 'No clients. Add on Clients page.'
                                        : 'Tap to select client (required for debt)'),
                                style: _selectedClient != null
                                    ? theme.textTheme.bodyMedium
                                    : theme.textTheme.bodySmall?.copyWith(
                                        color: _clients.isEmpty
                                            ? Colors.grey[600]
                                            : Colors.red[700],
                                        fontWeight: _clients.isEmpty
                                            ? null
                                            : FontWeight.w500,
                                      ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _cart.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No items added to this sale yet.\n'
                                'Select an item above to start.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            itemCount: _cart.length,
                            itemBuilder: (context, index) {
                              final entry = _cart[index];
                              final grossLineTotal =
                                  entry.item.sellingPrice * entry.quantity;
                              final discount = entry.productDiscount > grossLineTotal
                                  ? grossLineTotal
                                  : entry.productDiscount;
                              final lineTotal = grossLineTotal - discount;
                              final u = (entry.item.unitShort ??
                                      entry.item.unit ??
                                      '')
                                  .trim();
                              final unitLabel = u;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                elevation: 1.2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _editCartEntry(index),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            toTitleCaseWords(entry.item.name),
                                            if (_saleCategoryLabel(entry.item).isNotEmpty)
                                              _saleCategoryLabel(entry.item),
                                          ].join(' - '),
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${_fmtCompactNumber(entry.quantity)} $unitLabel  •  Unit: $_currencySymbol${_fmtMoney(entry.item.sellingPrice)}\n'
                                                'Disc: $_currencySymbol${_fmtMoney(discount)}  •  Total: $_currencySymbol${_fmtMoney(lineTotal)}',
                                                style: theme.textTheme.bodySmall,
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  icon: const Icon(Icons.edit_outlined),
                                                  tooltip: 'Edit quantity',
                                                  onPressed: () => _editCartEntry(index),
                                                ),
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  icon: const Icon(Icons.delete_outline),
                                                  onPressed: () {
                                                    setState(() {
                                                      _cart.removeAt(index);
                                                      if (_isAllReceived) {
                                                        _amountReceivedController.text =
                                                            _fmtCompactNumber(_liveTotal);
                                                      }
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Text(
                            'Total: $_currencySymbol${_fmtMoney(_liveTotal)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2563EB),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                    children: [
                      Radio<bool>(
                        value: true,
                        groupValue: _discountRadioSelected ? true : null,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (_) {
                          _openOverallDiscountScreen();
                        },
                      ),
                      const SizedBox(width: 0),
                      InkWell(
                        onTap: () {
                          _openOverallDiscountScreen();
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                          child: Text('Discount'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('|', style: theme.textTheme.labelMedium),
                      const SizedBox(width: 4),
                      Radio<_PaymentMode>(
                        value: _PaymentMode.all,
                        visualDensity: VisualDensity.compact,
                        groupValue: _paymentMode,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => _setPaymentMode(_PaymentMode.all),
                      ),
                      const SizedBox(width: 0),
                      InkWell(
                        onTap: () => _setPaymentMode(_PaymentMode.all),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                          child: Text('All'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Radio<_PaymentMode>(
                        value: _PaymentMode.partial,
                        visualDensity: VisualDensity.compact,
                        groupValue: _paymentMode,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => _setPaymentMode(_PaymentMode.partial),
                      ),
                      const SizedBox(width: 0),
                      InkWell(
                        onTap: () => _setPaymentMode(_PaymentMode.partial),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                          child: Text('Partial'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Radio<_PaymentMode>(
                        value: _PaymentMode.zeroPaid,
                        visualDensity: VisualDensity.compact,
                        groupValue: _paymentMode,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => _setPaymentMode(_PaymentMode.zeroPaid),
                      ),
                      const SizedBox(width: 0),
                      InkWell(
                        onTap: () => _setPaymentMode(_PaymentMode.zeroPaid),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                          child: Text('Zero'),
                        ),
                      ),
                    ],
                        ),
                        const SizedBox(height: 6),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Radio<_SalePaymentMethod>(
                              value: _SalePaymentMethod.cash,
                              visualDensity: VisualDensity.compact,
                              groupValue: _paymentMethod,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) {
                                if (v == null) return;
                                unawaited(_setSalePaymentMethod(v));
                              },
                            ),
                            InkWell(
                              onTap: () => unawaited(
                                _setSalePaymentMethod(_SalePaymentMethod.cash),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text('Cash'),
                              ),
                            ),
                            Radio<_SalePaymentMethod>(
                              value: _SalePaymentMethod.mobileMoney,
                              visualDensity: VisualDensity.compact,
                              groupValue: _paymentMethod,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) {
                                if (v == null) return;
                                unawaited(_setSalePaymentMethod(v));
                              },
                            ),
                            InkWell(
                              onTap: () => unawaited(
                                _setSalePaymentMethod(
                                  _SalePaymentMethod.mobileMoney,
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text('Mobile Money'),
                              ),
                            ),
                            Radio<_SalePaymentMethod>(
                              value: _SalePaymentMethod.account,
                              visualDensity: VisualDensity.compact,
                              groupValue: _paymentMethod,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) {
                                if (v == null) return;
                                unawaited(_setSalePaymentMethod(v));
                              },
                            ),
                            InkWell(
                              onTap: () => unawaited(
                                _setSalePaymentMethod(_SalePaymentMethod.account),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text('Account'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: _isAllReceived
                              ? TextField(
                                  controller: _amountReceivedController,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    prefixText: '$_currencySymbol ',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                )
                              : _paymentMode == _PaymentMode.zeroPaid
                              ? TextField(
                                  controller: _amountReceivedController,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    prefixText: '$_currencySymbol ',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                )
                              : TextField(
                                  controller: _amountReceivedController,
                                  readOnly: true,
                                  onTap: _openAmountReceivedPage,
                                  decoration: InputDecoration(
                                    hintText: 'Tap to set paid amount',
                                    prefixText: '$_currencySymbol ',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    suffixIcon: const Icon(Icons.arrow_drop_down),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _saveSale,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ),
                    ],
                        ),
                        if (_cartTotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _discountRadioSelected
                                        ? 'Overall discount: $_currencySymbol${_fmtMoney(_effectiveDiscount)}'
                                        : '',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Balance: $_currencySymbol${_fmtMoney(_liveTotal - (double.tryParse(_amountReceivedController.text.replaceAll(',', '.')) ?? 0))}',
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _SaleReceiptDialog extends StatefulWidget {
  const _SaleReceiptDialog({
    required this.saleId,
    required this.currencySymbol,
    required this.totalAmount,
    required this.overallDiscount,
    required this.amountReceived,
    required this.balance,
    required this.lines,
    this.onProceedToSalesHistory,
  });

  final int saleId;
  final String currencySymbol;
  final double totalAmount;
  final double overallDiscount;
  final double amountReceived;
  final double balance;
  final List<_SaleReceiptLine> lines;
  final VoidCallback? onProceedToSalesHistory;

  @override
  State<_SaleReceiptDialog> createState() => _SaleReceiptDialogState();
}

class _SaleReceiptDialogState extends State<_SaleReceiptDialog> {
  Timer? _autoCloseTicker;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = 20;
    _autoCloseTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _autoCloseTicker?.cancel();
        Navigator.of(context).pop();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _autoCloseTicker?.cancel();
    super.dispose();
  }

  void _goToSalesHistory() {
    _autoCloseTicker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onProceedToSalesHistory?.call();
  }

  String _fmtMoney(double value) => formatMoney(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = theme.colorScheme.primary;
    final grandSubtotal = widget.lines.fold<double>(
      0,
      (sum, line) => sum + line.netTotal,
    );
    return AlertDialog(
      title: const Text('Sale receipt'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Receipt: #${widget.saleId}'),
              const SizedBox(height: 4),
              Text('Items: ${widget.lines.length}'),
              const SizedBox(height: 10),
              Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {
                  0: FlexColumnWidth(2.2),
                  1: FlexColumnWidth(0.9),
                  2: FlexColumnWidth(1.1),
                  3: FlexColumnWidth(1),
                },
                children: [
                  const TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Item',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Qty',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Unit',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Total',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  ...widget.lines.map(
                    (line) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, right: 6),
                          child: Text(
                            line.unit.isEmpty
                                ? line.itemName
                                : '${line.itemName} (${line.unit})',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(formatDisplayNumber(line.quantity)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${widget.currencySymbol}${_fmtMoney(line.unitPrice)}',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${widget.currencySymbol}${_fmtMoney(line.netTotal)}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              _receiptSummaryRow(
                'Grand subtotal',
                '${widget.currencySymbol}${_fmtMoney(grandSubtotal)}',
              ),
              const SizedBox(height: 4),
              _receiptSummaryRow(
                'Overall discount',
                '${widget.currencySymbol}${_fmtMoney(widget.overallDiscount)}',
              ),
              const SizedBox(height: 6),
              _receiptSummaryRow(
                'Final total',
                '${widget.currencySymbol}${_fmtMoney(widget.totalAmount)}',
                bold: true,
              ),
              const SizedBox(height: 4),
              _receiptSummaryRow(
                'Paid',
                '${widget.currencySymbol}${_fmtMoney(widget.amountReceived)}',
              ),
              const SizedBox(height: 4),
              _receiptSummaryRow(
                'Balance',
                '${widget.currencySymbol}${_fmtMoney(widget.balance)}',
                bold: true,
              ),
              const SizedBox(height: 10),
              Text(
                'This receipt closes automatically in $_secondsLeft ${_secondsLeft == 1 ? 'second' : 'seconds'}.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: _goToSalesHistory,
                  child: Text(
                    'Proceed to the Sales history page',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: linkColor,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: linkColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _autoCloseTicker?.cancel();
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _receiptSummaryRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
        ),
      ],
    );
  }
}

class _SaveDraftNameScreen extends StatefulWidget {
  const _SaveDraftNameScreen({required this.initialTitle});

  final String initialTitle;

  @override
  State<_SaveDraftNameScreen> createState() => _SaveDraftNameScreenState();
}

class _SaveDraftNameScreenState extends State<_SaveDraftNameScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Save cart draft')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Draft name',
                  hintText: 'e.g. Customer or table',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (value) =>
                    Navigator.of(context).pop(value.trim()),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

