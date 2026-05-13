import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/item.dart';
import '../models/unit.dart';
import '../services/auth_service.dart';
import '../services/item_image_upload_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../widgets/section_page_title.dart';
import 'barcode_scan_screen.dart';

class ItemEditScreen extends StatefulWidget {
  final Item? item;

  const ItemEditScreen({super.key, this.item});

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final List<String> _saleCategories = ['Retail', 'Wholesale', 'Service'];
  final List<String> _businessCategories = ['Supermarket', 'Hardware'];

  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _skuController;
  late final TextEditingController _shelfNumberController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _reorderController;
  late final TextEditingController _restockToController;

  bool _saving = false;
  bool _uploadingImage = false;
  List<Unit> _units = [];
  bool _unitsLoading = true;
  Unit? _selectedUnit;
  String? _selectedSaleCategory;
  String? _selectedBusinessCategory;
  final List<String?> _imageUrls = <String?>[null, null, null];
  List<String> _recentImageUrls = const [];

  String _initialNumberText(double? value) {
    final v = value ?? 0;
    if (v == 0) return '';
    return v.toString();
  }

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _barcodeController = TextEditingController(text: item?.barcode ?? '');
    _skuController = TextEditingController(text: item?.sku ?? '');
    _shelfNumberController =
        TextEditingController(text: item?.shelfNumber ?? '');
    _costController =
        TextEditingController(text: _initialNumberText(item?.costPrice));
    _priceController =
        TextEditingController(text: _initialNumberText(item?.sellingPrice));
    _stockController =
        TextEditingController(text: _initialNumberText(item?.stockQty));
    _reorderController =
        TextEditingController(text: _initialNumberText(item?.reorderLevel));
    _restockToController =
        TextEditingController(text: _initialNumberText(item?.restockTo));
    _setCategorySelections(item?.category);
    _imageUrls[0] = item?.imageUrl;
    _imageUrls[1] = item?.imageUrl2;
    _imageUrls[2] = item?.imageUrl3;
    _nameController.addListener(_onNameChanged);
    _loadUnits();
    _loadRecentImageUrls();
    _loadAcceptedBarcodes();
    _ensurePrimaryCodeVisible();
  }

  void _onNameChanged() {
    _loadRecentImageUrls();
  }

  List<String> _enteredBarcodes() {
    return _parseAcceptedBarcodes(_barcodeController.text);
  }

  void _setEnteredBarcodes(Iterable<String> values) {
    _barcodeController.text = _db.normalizeBarcodeList(values).join(', ');
  }

  Future<void> _tryAddBarcodeCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || !mounted) return;
    final normalized = _norm(trimmed);
    final current = _enteredBarcodes();
    final alreadyAdded = current.any((e) => _norm(e) == normalized);
    if (alreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Code "$trimmed" is already added to this item.')),
      );
      return;
    }

    final existingItems = await _loadItemsForBarcodeChecks();
    final conflictInLoaded = existingItems.firstWhere(
      (item) =>
          item.id != widget.item?.id &&
          (_norm(item.sku) == normalized || _norm(item.barcode) == normalized),
      orElse: () => Item(name: ''),
    );
    if (conflictInLoaded.name.trim().isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Code "$trimmed" is already used by item "${conflictInLoaded.name}".',
          ),
        ),
      );
      return;
    }

    if (!await _auth.isRemoteUser()) {
      final localConflict = await _db.findItemByAnyCode(
        trimmed,
        excludingItemId: widget.item?.id,
      );
      if (localConflict != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Code "$trimmed" is already used by item "${localConflict.name}".',
            ),
          ),
        );
        return;
      }
    }

    final merged = _db.normalizeBarcodeList([...current, trimmed]);
    if (!mounted) return;
    setState(() => _setEnteredBarcodes(merged));
  }

  Future<void> _scanAndAppendBarcode() async {
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
    final scanned = code.trim();
    if (scanned.isEmpty) return;
    await _tryAddBarcodeCode(scanned);
  }

  Future<void> _promptAndAddBarcode() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode',
            hintText: 'Type barcode and save',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final code = (raw ?? '').trim();
    if (code.isEmpty || !mounted) return;
    await _tryAddBarcodeCode(code);
  }

  List<String> _parseAcceptedBarcodes(String raw) {
    final segments = raw
        .split(RegExp(r'[\n,;|]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return _db.normalizeBarcodeList(segments);
  }

  Future<void> _loadAcceptedBarcodes() async {
    final itemId = widget.item?.id;
    if (itemId == null) return;
    final aliases = await _db.getItemBarcodes(itemId);
    if (!mounted || aliases.isEmpty) return;
    final allCodes = _db.normalizeBarcodeList([
      _barcodeController.text.trim(),
      ...aliases,
    ]);
    setState(() => _barcodeController.text = allCodes.join(', '));
  }

  Future<List<Item>> _loadItemsForBarcodeChecks() async {
    if (await _auth.isRemoteUser()) {
      return RemoteSyncService.instance.fetchItems();
    }
    return _db.getItems();
  }

  Future<void> _ensurePrimaryCodeVisible() async {
    final existing = _skuController.text.trim();
    if (existing.isNotEmpty) return;
    final generated = await _generateNextPrimaryCodeFromItems();
    if (!mounted) return;
    setState(() => _skuController.text = generated);
  }

  Future<String> _generateNextPrimaryCodeFromItems() async {
    final items = await _loadItemsForBarcodeChecks();
    final taken = <String>{};
    const prefix = 'ITM';
    final pattern = RegExp(r'^ITM(\d{6})$');
    var next = 1;
    for (final item in items) {
      if (item.id == widget.item?.id) continue;
      final sku = (item.sku ?? '').trim().toUpperCase();
      final barcode = (item.barcode ?? '').trim().toUpperCase();
      if (sku.isNotEmpty) taken.add(sku);
      if (barcode.isNotEmpty) taken.add(barcode);
      final skuMatch = pattern.firstMatch(sku);
      final skuNumber = int.tryParse(skuMatch?.group(1) ?? '');
      if (skuNumber != null && skuNumber >= next) next = skuNumber + 1;
      final barcodeMatch = pattern.firstMatch(barcode);
      final barcodeNumber = int.tryParse(barcodeMatch?.group(1) ?? '');
      if (barcodeNumber != null && barcodeNumber >= next) {
        next = barcodeNumber + 1;
      }
    }
    while (true) {
      final candidate = '$prefix${next.toString().padLeft(6, '0')}';
      if (!taken.contains(candidate)) return candidate;
      next++;
    }
  }

  Future<void> _refreshCategoryListsFromMother() async {
    final saleSet = <String>{'Retail', 'Wholesale', 'Service'};
    final businessSet = <String>{'Supermarket', 'Hardware'};
    final isRemote = await _auth.isRemoteUser();

    if (isRemote) {
      final sale = await _auth.fetchRemoteItemCategories(type: 'sale');
      final business = await _auth.fetchRemoteItemCategories(type: 'business');
      saleSet.addAll(sale);
      businessSet.addAll(business);
    } else {
      final rows = (await _db.getItems()).map((e) => e.toMap()).toList();
      for (final row in rows) {
        final rawCategory = (row['category'] ?? '').toString();
        final parsed = _extractCategories(rawCategory);
        final sale = (parsed.sale ?? '').trim();
        final business = (parsed.business ?? '').trim();
        if (sale.isNotEmpty) saleSet.add(sale);
        if (business.isNotEmpty) businessSet.add(business);
      }
    }

    if (!mounted) return;
    setState(() {
      _saleCategories
        ..clear()
        ..addAll(saleSet.toList()..sort((a, b) => _norm(a).compareTo(_norm(b))));
      _businessCategories
        ..clear()
        ..addAll(
          businessSet.toList()..sort((a, b) => _norm(a).compareTo(_norm(b))),
        );
    });
  }

  Future<void> _loadUnits() async {
    final isRemote = await _auth.isRemoteUser();
    final list = isRemote
        ? await RemoteSyncService.instance.fetchUnits()
        : await _db.getUnits();
    if (mounted) {
      Unit? initial;
      final item = widget.item;
      if ((item?.unit ?? '').trim().isNotEmpty) {
        final itemUnit = (item?.unit ?? '').trim().toLowerCase();
        final itemUnitShort = (item?.unitShort ?? '').trim().toLowerCase();

        // Prefer exact unit+short match, but fall back to unit-name-only match
        // so existing items still prefill even when short name differs remotely.
        initial = list
            .where((u) =>
                u.unitName.trim().toLowerCase() == itemUnit &&
                u.unitShortName.trim().toLowerCase() == itemUnitShort)
            .firstOrNull;
        initial ??= list
            .where((u) => u.unitName.trim().toLowerCase() == itemUnit)
            .firstOrNull;
      }
      setState(() {
        _units = list;
        _unitsLoading = false;
        if (initial != null) _selectedUnit = initial;
      });
    }
  }

  Future<void> _refreshUnitsForPicker() async {
    final isRemote = await _auth.isRemoteUser();
    final list = isRemote
        ? await RemoteSyncService.instance.fetchUnits()
        : await _db.getUnits();
    if (!mounted) return;

    final currentSelected = _selectedUnit;
    Unit? refreshedSelected;
    if (currentSelected != null) {
      refreshedSelected = list
          .where((u) => u.id != null && u.id == currentSelected.id)
          .firstOrNull;
      refreshedSelected ??= list
          .where((u) => _norm(u.displayLabel) == _norm(currentSelected.displayLabel))
          .firstOrNull;
    }

    setState(() {
      _units = list;
      _unitsLoading = false;
      if (refreshedSelected != null) {
        _selectedUnit = refreshedSelected;
      }
    });
  }

  void _setCategorySelections(String? categoryValue) {
    final raw = (categoryValue ?? '').trim();
    if (raw.isEmpty) return;
    final parts = raw.split('|').map((p) => p.trim()).toList();
    for (final part in parts) {
      if (part.startsWith('Sale:')) {
        final value = part.replaceFirst('Sale:', '').trim();
        if (_saleCategories.contains(value)) _selectedSaleCategory = value;
      }
      if (part.startsWith('Business:')) {
        final value = part.replaceFirst('Business:', '').trim();
        if (_businessCategories.contains(value)) _selectedBusinessCategory = value;
      }
    }
    if (_selectedBusinessCategory == null && _businessCategories.contains(raw)) {
      _selectedBusinessCategory = raw;
    }
    if (_selectedSaleCategory == null && _saleCategories.contains(raw)) {
      _selectedSaleCategory = raw;
    }
  }

  String? _composedCategoryValue() {
    final sale = _selectedSaleCategory?.trim();
    final business = _selectedBusinessCategory?.trim();
    if ((sale == null || sale.isEmpty) && (business == null || business.isEmpty)) {
      return null;
    }
    if (sale != null && sale.isNotEmpty && business != null && business.isNotEmpty) {
      return 'Business: $business | Sale: $sale';
    }
    if (business != null && business.isNotEmpty) return 'Business: $business';
    return 'Sale: $sale';
  }

  ({String? sale, String? business}) _extractCategories(String? categoryValue) {
    final raw = (categoryValue ?? '').trim();
    String? sale;
    String? business;
    if (raw.isNotEmpty) {
      final parts = raw.split('|').map((p) => p.trim());
      for (final part in parts) {
        if (part.startsWith('Sale:')) {
          sale = part.replaceFirst('Sale:', '').trim();
        } else if (part.startsWith('Business:')) {
          business = part.replaceFirst('Business:', '').trim();
        }
      }
      if (sale == null && _saleCategories.contains(raw)) sale = raw;
      if (business == null && _businessCategories.contains(raw)) business = raw;
    }
    return (sale: sale, business: business);
  }

  String _norm(String? value) => (value ?? '').trim().toLowerCase();

  bool get _isServiceSaleCategory => _norm(_selectedSaleCategory) == 'service';

  Future<void> _showAddCategoryDialog({required bool isSaleCategory}) async {
    final controller = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSaleCategory ? 'Add sale category' : 'Add business category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final value = (created ?? '').trim();
    if (value.isEmpty) return;
    final source = isSaleCategory ? _saleCategories : _businessCategories;
    if (source.any((e) => _norm(e) == _norm(value))) return;
    final isRemote = await _auth.isRemoteUser();
    if (isRemote) {
      final remote = await _auth.saveRemoteItemCategory(
        type: isSaleCategory ? 'sale' : 'business',
        name: value,
      );
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((remote['message'] ?? 'Could not add category').toString()),
          ),
        );
        return;
      }
      await _refreshCategoryListsFromMother();
    } else {
      if (!mounted) return;
      setState(() {
        source.add(value);
        source.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });
    }
    if (!mounted) return;
    setState(() {
      if (isSaleCategory) {
        _selectedSaleCategory = value;
      } else {
        _selectedBusinessCategory = value;
      }
    });
  }

  Future<void> _showEditCategoryDialog({
    required bool isSaleCategory,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSaleCategory ? 'Edit sale category' : 'Edit business category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = (updated ?? '').trim();
    if (value.isEmpty) return;
    final source = isSaleCategory ? _saleCategories : _businessCategories;
    final existingIdx = source.indexWhere((e) => _norm(e) == _norm(initialValue));
    if (existingIdx < 0) return;
    if (source.any((e) => _norm(e) == _norm(value) && _norm(e) != _norm(initialValue))) {
      return;
    }
    final isRemote = await _auth.isRemoteUser();
    if (isRemote) {
      final remote = await _auth.saveRemoteItemCategory(
        type: isSaleCategory ? 'sale' : 'business',
        name: value,
        oldName: initialValue,
      );
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((remote['message'] ?? 'Could not update category').toString()),
          ),
        );
        return;
      }
      await _refreshCategoryListsFromMother();
    } else {
      if (!mounted) return;
      setState(() {
        source[existingIdx] = value;
        source.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });
    }
    if (!mounted) return;
    setState(() {
      if (isSaleCategory && _norm(_selectedSaleCategory) == _norm(initialValue)) {
        _selectedSaleCategory = value;
      }
      if (!isSaleCategory && _norm(_selectedBusinessCategory) == _norm(initialValue)) {
        _selectedBusinessCategory = value;
      }
    });
  }

  Future<void> _deleteSelectedCategory({
    required bool isSaleCategory,
    String? targetValue,
  }) async {
    final value = (targetValue ?? '').trim();
    if (value.isEmpty) return;
    final source = isSaleCategory ? _saleCategories : _businessCategories;
    final idx = source.indexWhere((e) => _norm(e) == _norm(value));
    if (idx < 0) return;
    final isRemote = await _auth.isRemoteUser();
    if (isRemote) {
      final remote = await _auth.deleteRemoteItemCategory(
        type: isSaleCategory ? 'sale' : 'business',
        name: value,
      );
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((remote['message'] ?? 'Could not delete category').toString()),
          ),
        );
        return;
      }
      await _refreshCategoryListsFromMother();
    } else {
      if (!mounted) return;
      setState(() => source.removeAt(idx));
    }
    if (!mounted) return;
    setState(() {
      if (isSaleCategory && _norm(_selectedSaleCategory) == _norm(value)) {
        _selectedSaleCategory = null;
      }
      if (!isSaleCategory && _norm(_selectedBusinessCategory) == _norm(value)) {
        _selectedBusinessCategory = null;
      }
    });
  }

  Future<void> _showEditUnitDialog(Unit unit) async {
    final unitNameController = TextEditingController(text: unit.unitName);
    final shortNameController = TextEditingController(text: unit.unitShortName);
    final updated = await showDialog<Unit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitNameController,
              decoration: const InputDecoration(labelText: 'Unit name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: shortNameController,
              decoration: const InputDecoration(labelText: 'Short name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final unitName = unitNameController.text.trim();
              final shortName = shortNameController.text.trim();
              if (unitName.isEmpty || shortName.isEmpty) return;
              Navigator.of(context).pop(
                Unit(id: unit.id, unitName: unitName, unitShortName: shortName),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null) return;
    try {
      final isRemote = await _auth.isRemoteUser();
      if (isRemote) {
        final remote = await _auth.saveRemoteUnit({
          'id': updated.id,
          'unit_name': updated.unitName,
          'unit_short_name': updated.unitShortName,
        });
        if (remote['success'] != true) {
          throw StateError((remote['message'] ?? 'Could not update unit').toString());
        }
      } else {
        await _db.updateUnit(updated);
      }
      await _loadUnits();
      if (!mounted) return;
      final selected = _units.where((u) => u.id == updated.id).firstOrNull;
      if (selected != null) {
        setState(() => _selectedUnit = selected);
      }
    } catch (_) {}
  }

  Future<void> _deleteUnit(Unit unit) async {
    if (unit.id == null) return;
    try {
      final isRemote = await _auth.isRemoteUser();
      if (isRemote) {
        await _auth.deleteRemoteUnit(unit.id!);
      } else {
        await _db.deleteUnit(unit.id!);
      }
      await _loadUnits();
      if (!mounted) return;
      if (_selectedUnit?.id == unit.id) {
        setState(() => _selectedUnit = null);
      }
    } catch (_) {}
  }

  Future<void> _showOptionPicker<T>({
    required String title,
    required List<T> options,
    required String? selectedValue,
    required String Function(T) labelOf,
    required Future<void> Function() onAddNew,
    required Future<void> Function(T value) onEditOption,
    required Future<void> Function(T value) onDeleteOption,
    required void Function(String? value) onSelected,
  }) async {
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final filtered = options
                .where((e) => labelOf(e).toLowerCase().contains(query.toLowerCase()))
                .toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: 'Search',
                                prefixIcon: Icon(Icons.search, size: 18),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                isDense: true,
                              ),
                              onChanged: (value) =>
                                  setLocal(() => query = value.trim()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await onAddNew();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add new'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final isSelected = selectedValue == null;
                            return ListTile(
                              dense: true,
                              title: const Text('None'),
                              trailing: isSelected
                                  ? const Icon(Icons.check, color: Color(0xFF2563EB))
                                  : null,
                              onTap: () {
                                onSelected(null);
                                Navigator.of(context).pop();
                              },
                            );
                          }
                          final option = filtered[index - 1];
                          final label = labelOf(option);
                          final isSelected = _norm(selectedValue) == _norm(label);
                          return ListTile(
                            dense: true,
                            title: Text(label),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.check, color: Color(0xFF2563EB)),
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () async {
                                    await onEditOption(option);
                                    if (context.mounted) Navigator.of(context).pop();
                                  },
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () async {
                                    await onDeleteOption(option);
                                    if (context.mounted) Navigator.of(context).pop();
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              onSelected(label);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddUnitDialog() async {
    final unitNameController = TextEditingController();
    final shortNameController = TextEditingController();
    final created = await showDialog<Unit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitNameController,
              decoration: const InputDecoration(labelText: 'Unit name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: shortNameController,
              decoration: const InputDecoration(labelText: 'Short name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final unitName = unitNameController.text.trim();
              final shortName = shortNameController.text.trim();
              if (unitName.isEmpty || shortName.isEmpty) return;
              Navigator.of(context).pop(
                Unit(unitName: unitName, unitShortName: shortName),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (created == null) return;
    try {
      final isRemote = await _auth.isRemoteUser();
      if (isRemote) {
        final remote = await _auth.saveRemoteUnit({
          'unit_name': created.unitName,
          'unit_short_name': created.unitShortName,
        });
        if (remote['success'] != true) {
          throw StateError((remote['message'] ?? 'Could not add unit').toString());
        }
      } else {
        await _db.insertUnit(created);
      }
      await _loadUnits();
      if (!mounted) return;
      final selected = _units
          .where(
            (u) =>
                u.unitName.toLowerCase() == created.unitName.toLowerCase() &&
                u.unitShortName.toLowerCase() ==
                    created.unitShortName.toLowerCase(),
          )
          .firstOrNull;
      if (selected != null) {
        setState(() => _selectedUnit = selected);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit added')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add unit')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _shelfNumberController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _restockToController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentImageUrls() async {
    final nameKey = _norm(_nameController.text);
    if (nameKey.isEmpty) {
      if (_recentImageUrls.isNotEmpty && mounted) {
        setState(() => _recentImageUrls = const []);
      }
      return;
    }
    final items = await _db.getItems();
    if (!mounted) return;
    final urls = <String>[];
    for (final item in items) {
      if (_norm(item.name) != nameKey) continue;
      final candidates = [
        (item.imageUrl ?? '').trim(),
        (item.imageUrl2 ?? '').trim(),
        (item.imageUrl3 ?? '').trim(),
      ];
      for (final url in candidates) {
        if (url.isEmpty || urls.contains(url)) continue;
        urls.add(url);
        if (urls.length >= 8) break;
      }
      if (urls.length >= 8) break;
    }
    setState(() => _recentImageUrls = urls);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    final cost =
        double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
    final base = widget.item;
    final isService = _isServiceSaleCategory;
    final isNewItem = base == null;
    final stock = isService
        ? (isNewItem ? 1.0 : 0.0)
        : (double.tryParse(_stockController.text.replaceAll(',', '.')) ?? 0);
    final reorder = isService
        ? 0.0
        : (double.tryParse(_reorderController.text.replaceAll(',', '.')) ?? 0);
    final restockTo = isService
        ? 0.0
        : (double.tryParse(_restockToController.text.replaceAll(',', '.')) ??
            0);

    final categoryValue = _composedCategoryValue();
    final enteredBarcodes = _parseAcceptedBarcodes(_barcodeController.text);
    final enteredSku = _skuController.text.trim();
    final shelfNumber = _shelfNumberController.text.trim();

    List<Item> existingItems = const [];
    existingItems = await _loadItemsForBarcodeChecks();
    final allCodesToValidate = [
      if (enteredSku.isNotEmpty) enteredSku,
      ...enteredBarcodes,
    ];
    String? conflictingCode;
    for (final code in allCodesToValidate) {
      final normalized = _norm(code);
      if (normalized.isEmpty) continue;
      final usedByOtherItem = existingItems.any(
        (e) =>
            e.id != base?.id &&
            (_norm(e.sku) == normalized || _norm(e.barcode) == normalized),
      );
      if (usedByOtherItem) {
        conflictingCode = code.trim();
        break;
      }
    }
    conflictingCode ??= await _db.findConflictingBarcode(
      allCodesToValidate,
      excludingItemId: base?.id,
    );
    if (conflictingCode != null) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code "$conflictingCode" is already used by another item.'),
        ),
      );
      return;
    }

    final resolvedSku = enteredSku.isEmpty
        ? await _db.generateNextInternalSku()
        : enteredSku;
    final primaryBarcode = resolvedSku;
    final aliasBarcodes = _db
        .normalizeBarcodeList(enteredBarcodes)
        .where((code) => _norm(code) != _norm(resolvedSku))
        .toList();

    // For new items: block only exact duplicates of name + unit + sale + business.
    if (base == null) {
      final selectedSale = _norm(_selectedSaleCategory);
      final selectedBusiness = _norm(_selectedBusinessCategory);
      final selectedUnit = _norm(_selectedUnit?.unitName);
      final selectedName = _norm(_nameController.text);

      final hasExactDuplicate = existingItems.any((e) {
        final parsed = _extractCategories(e.category);
        return _norm(e.name) == selectedName &&
            _norm(e.unit) == selectedUnit &&
            _norm(parsed.sale) == selectedSale &&
            _norm(parsed.business) == selectedBusiness;
      });

      if (hasExactDuplicate) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This item already exists with same name, unit, sale category and business category.',
            ),
          ),
        );
        return;
      }
    }

    final newItem = Item(
      id: base?.id,
      storeId: base?.storeId,
      name: _nameController.text.trim(),
      barcode: primaryBarcode,
      sku: resolvedSku,
      category: categoryValue,
      unit: _selectedUnit?.unitName,
      unitShort: _selectedUnit?.unitShortName,
      shelfNumber: shelfNumber.isEmpty ? null : shelfNumber,
      imageUrl: _imageUrls[0],
      imageUrl2: _imageUrls[1],
      imageUrl3: _imageUrls[2],
      packagingId: null,
      variantGroup: null,
      unitsPerPackage: null,
      costPrice: cost,
      sellingPrice: price,
      stockQty: stock,
      reorderLevel: reorder,
      restockTo: restockTo,
      createdAt: base?.createdAt,
    );

    if (await _auth.isRemoteUser()) {
      final remote = await _auth.saveRemoteItem({
        'id': newItem.id,
        'store_id': newItem.storeId,
        'name': newItem.name,
        'barcode': newItem.barcode,
        'sku': newItem.sku,
        'category': newItem.category,
        'unit': newItem.unit,
        'unit_short': newItem.unitShort,
        'shelf_number': newItem.shelfNumber,
        'image_url': newItem.imageUrl,
        'image_url_2': newItem.imageUrl2,
        'image_url_3': newItem.imageUrl3,
        'packaging_id': newItem.packagingId,
        'variant_group': newItem.variantGroup,
        'units_per_package': newItem.unitsPerPackage,
        'cost_price': newItem.costPrice,
        'selling_price': newItem.sellingPrice,
        'stock_qty': newItem.stockQty,
        'reorder_level': newItem.reorderLevel,
        'restock_to': newItem.restockTo,
        'created_at': newItem.createdAt.toIso8601String(),
      });
      if (remote['success'] != true) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((remote['message'] ?? 'Failed to sync item').toString())),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
      Navigator.of(context).pop(true);
      return;
    }

    final persistedItemId = base?.id ?? (await _db.upsertItem(newItem));
    if (base != null) {
      await _db.upsertItem(newItem);
    }
    if (persistedItemId > 0) {
      await _db.replaceItemBarcodes(
        itemId: persistedItemId,
        barcodes: aliasBarcodes,
      );
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    Navigator.of(context).pop(true);
  }

  bool _hasImageAt(int index) {
    final value = _imageUrls[index];
    return value != null && value.trim().isNotEmpty;
  }

  int _nextImageSlot() {
    for (var i = 0; i < _imageUrls.length; i++) {
      if (!_hasImageAt(i)) return i;
    }
    return 0;
  }

  Future<void> _uploadImage([int? targetIndex]) async {
    if (_uploadingImage || _saving) return;
    final slot = targetIndex ?? _nextImageSlot();
    setState(() => _uploadingImage = true);
    try {
      final url = await ItemImageUploadService.instance.pickCompressAndUpload();
      if (!mounted) return;
      setState(() => _imageUrls[slot] = url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image ${slot + 1} uploaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = '$e'.contains('_UserCancelledException')
          ? 'Image selection cancelled.'
          : 'Image upload failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: SectionPageTitle(
          pageTitle: isEditing ? 'Edit item' : 'New item',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Item images (up to 3)',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(_imageUrls.length, (index) {
                  final imageUrl = _imageUrls[index];
                  final hasImage = _hasImageAt(index);
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == _imageUrls.length - 1 ? 0 : 8,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 88,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: hasImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        size: 26,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.image_outlined, size: 26),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton(
                            onPressed: _uploadingImage
                                ? null
                                : () => _uploadImage(index),
                            child: Text(
                              _uploadingImage ? 'Uploading...' : 'Upload',
                            ),
                          ),
                          if (hasImage)
                            TextButton(
                              onPressed: _uploadingImage
                                  ? null
                                  : () =>
                                      setState(() => _imageUrls[index] = null),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              if (_recentImageUrls.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Recently used images for this item',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentImageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final url = _recentImageUrls[index];
                      final selected = _imageUrls.contains(url);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _saving || _uploadingImage
                            ? null
                            : () => setState(
                                () => _imageUrls[_nextImageSlot()] = url,
                              ),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF2563EB)
                                  : Colors.grey.shade300,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Accepted barcodes (optional)',
                        helperText:
                            'Scan repeatedly to add many codes. Primary code is your auto-generated SKU.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Scan barcode with camera',
                    onPressed: _saving ? null : _scanAndAppendBarcode,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                  IconButton(
                    tooltip: 'Type and add barcode',
                    onPressed: _saving ? null : _promptAndAddBarcode,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_enteredBarcodes().isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _enteredBarcodes().map((code) {
                    return InputChip(
                      label: Text(code),
                      onDeleted: _saving
                          ? null
                          : () {
                              final next = _enteredBarcodes()
                                  .where((e) => _norm(e) != _norm(code))
                                  .toList();
                              setState(() => _setEnteredBarcodes(next));
                            },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _skuController,
                readOnly: true,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Primary code (auto-generated)',
                  helperText:
                      'This is the fixed primary code for the item.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shelfNumberController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Shelf number (optional)',
                  helperText: 'Example: A-03, R2-S1',
                ),
              ),
              const SizedBox(height: 12),
              FormField<String>(
                initialValue: _selectedBusinessCategory,
                builder: (state) {
                  return InkWell(
                    onTap: () async {
                      await _refreshCategoryListsFromMother();
                      if (!mounted) return;
                      await _showOptionPicker<String>(
                        title: 'Business categories',
                        options: _businessCategories,
                        selectedValue: _selectedBusinessCategory,
                        labelOf: (e) => e,
                        onAddNew: () => _showAddCategoryDialog(isSaleCategory: false),
                        onEditOption: (value) => _showEditCategoryDialog(
                          isSaleCategory: false,
                          initialValue: value,
                        ),
                        onDeleteOption: (value) => _deleteSelectedCategory(
                          isSaleCategory: false,
                          targetValue: value,
                        ),
                        onSelected: (value) =>
                            setState(() => _selectedBusinessCategory = value),
                      );
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Business category (optional)',
                      ),
                      child: Text(_selectedBusinessCategory ?? 'None'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              if (_unitsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                FormField<Unit>(
                  initialValue: _selectedUnit,
                  builder: (state) {
                    return InkWell(
                      onTap: () async {
                        await _refreshUnitsForPicker();
                        if (!mounted) return;
                        await _showOptionPicker<Unit>(
                          title: 'Units',
                          options: _units,
                          selectedValue: _selectedUnit?.displayLabel,
                          labelOf: (u) => u.displayLabel,
                          onAddNew: _showAddUnitDialog,
                          onEditOption: _showEditUnitDialog,
                          onDeleteOption: _deleteUnit,
                          onSelected: (value) {
                            final selected = _units
                                .where((u) => _norm(u.displayLabel) == _norm(value))
                                .firstOrNull;
                            setState(() => _selectedUnit = selected);
                          },
                        );
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Unit (optional)'),
                        child: Text(_selectedUnit?.displayLabel ?? 'None'),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  await _refreshCategoryListsFromMother();
                  if (!mounted) return;
                  await _showOptionPicker<String>(
                    title: 'Sale categories',
                    options: _saleCategories,
                    selectedValue: _selectedSaleCategory,
                    labelOf: (e) => e,
                    onAddNew: () => _showAddCategoryDialog(isSaleCategory: true),
                    onEditOption: (value) => _showEditCategoryDialog(
                      isSaleCategory: true,
                      initialValue: value,
                    ),
                    onDeleteOption: (value) => _deleteSelectedCategory(
                      isSaleCategory: true,
                      targetValue: value,
                    ),
                    onSelected: (value) =>
                        setState(() => _selectedSaleCategory = value),
                  );
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Sale category (optional)',
                  ),
                  child: Text(_selectedSaleCategory ?? 'None'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pricing',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cost price',
                        helperText: 'Optional: set initial unit cost',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Selling price',
                        helperText: 'Optional: set initial unit selling price',
                      ),
                    ),
                  ),
                ],
              ),
              // Non-service items only (same screen for New item + Edit item).
              if (!_isServiceSaleCategory) ...[
                const SizedBox(height: 16),
                Text(
                  'Stock',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Stock quantity',
                          helperText: 'Optional: set initial stock quantity',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Reorder level',
                          helperText:
                              'Alert when stock is at or below this level',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _restockToController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Restock to',
                    helperText:
                        'Target stock level after ordering new stock',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Saving...' : 'Save item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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

