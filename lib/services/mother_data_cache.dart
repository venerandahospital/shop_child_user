import '../models/client.dart';
import '../models/item.dart';
import '../models/store.dart';
import '../utils/meter_fixed_stock_items.dart';

/// In-memory read models for the child **frontend**. The mother app is the server:
/// authoritative data lives in the mother's DB; this cache only reflects recent
/// GET responses so list screens stay fast without writing business rows to
/// SQLite here. Screens that call [LocalDbService] getters for these entities use
/// this cache after [RemoteSyncService] or fetch methods have populated it.
class MotherDataCache {
  MotherDataCache._();
  static final MotherDataCache instance = MotherDataCache._();

  List<Map<String, Object?>> _itemRows = [];
  List<Map<String, Object?>> _storeRows = [];
  List<Map<String, Object?>> _clientRows = [];
  final Map<int, List<String>> _itemBarcodeAliasesByItemId = {};

  bool itemsApplied = false;
  bool storesApplied = false;
  bool clientsApplied = false;

  void clear() {
    _itemRows = [];
    _storeRows = [];
    _clientRows = [];
    _itemBarcodeAliasesByItemId.clear();
    itemsApplied = false;
    storesApplied = false;
    clientsApplied = false;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  String _toIsoNowIfEmpty(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    return raw.isEmpty ? DateTime.now().toIso8601String() : raw;
  }

  Map<String, Object?> _normalizeStoreRow(Map<dynamic, dynamic> row) {
    final isDef = row['is_default'] == true ||
        row['isDefault'] == true ||
        '${row['is_default']}'.trim() == '1';
    return {
      'id': _toInt(row['id']),
      'name': (row['name'] ?? '').toString(),
      'description': row['description']?.toString(),
      'is_default': isDef ? 1 : 0,
      'created_at': _toIsoNowIfEmpty(row['created_at'] ?? row['createdAt']),
    };
  }

  Map<String, Object?> _normalizeClientRow(Map<dynamic, dynamic> row) {
    return {
      'id': _toInt(row['id']),
      'store_id': _toInt(row['store_id'] ?? row['storeId']),
      'name': (row['name'] ?? '').toString(),
      'phone': row['phone']?.toString(),
      'address': row['address']?.toString(),
      'created_at': _toIsoNowIfEmpty(row['created_at'] ?? row['createdAt']),
    };
  }

  Map<String, Object?> _normalizeItemRow(Map<dynamic, dynamic> row) {
    return {
      'id': _toInt(row['id']),
      'store_id': _toInt(row['store_id'] ?? row['storeId']),
      'name': (row['name'] ?? '').toString(),
      'sku': row['sku']?.toString(),
      'barcode': row['barcode']?.toString(),
      'category': row['category']?.toString(),
      'unit': row['unit']?.toString(),
      'unit_short': (row['unit_short'] ?? row['unitShort'])?.toString(),
      'shelf_number': (row['shelf_number'] ?? row['shelfNumber'])?.toString(),
      'image_url': (row['image_url'] ?? row['imageUrl'])?.toString(),
      'image_url_2': (row['image_url_2'] ?? row['imageUrl2'])?.toString(),
      'image_url_3': (row['image_url_3'] ?? row['imageUrl3'])?.toString(),
      'packaging_id': _toInt(row['packaging_id'] ?? row['packagingId']),
      'variant_group': (row['variant_group'] ?? row['variantGroup'])?.toString(),
      'units_per_package':
          _toDouble(row['units_per_package'] ?? row['unitsPerPackage']),
      'cost_price': _toDouble(row['cost_price'] ?? row['costPrice']),
      'selling_price': _toDouble(row['selling_price'] ?? row['sellingPrice']),
      'stock_qty': _toDouble(row['stock_qty'] ?? row['stockQty']),
      'reorder_level': _toDouble(row['reorder_level'] ?? row['reorderLevel']),
      'restock_to': _toDouble(row['restock_to'] ?? row['restockTo']),
      'special_roll_meters_total': _toDouble(
        row['special_roll_meters_total'] ?? row['specialRollMetersTotal'],
      ),
      'special_roll_meters_sold': _toDouble(
        row['special_roll_meters_sold'] ?? row['specialRollMetersSold'],
      ),
      'created_at': _toIsoNowIfEmpty(row['created_at'] ?? row['createdAt']),
    };
  }

  void applyStoresFromRemote(List<Map<String, dynamic>> rows) {
    _storeRows = [
      for (final r in rows)
        _normalizeStoreRow(r),
    ];
    storesApplied = true;
  }

  void applyClientsFromRemote(List<Map<String, dynamic>> rows) {
    _clientRows = [
      for (final r in rows)
        _normalizeClientRow(r),
    ];
    clientsApplied = true;
  }

  List<String> _parseAcceptedBarcodesFromRow(Map<dynamic, dynamic> row) {
    final raw = row['accepted_barcodes'] ?? row['acceptedBarcodes'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        e.toString().trim(),
    ].where((s) => s.isNotEmpty).toList();
  }

  void applyItemsFromRemote(List<Map<String, dynamic>> rows) {
    _itemBarcodeAliasesByItemId.clear();
    final normalized = <Map<String, Object?>>[];
    for (final r in rows) {
      final map = _normalizeItemRow(r);
      normalized.add(map);
      final id = map['id'] as int?;
      if (id != null && id > 0) {
        final aliases = _parseAcceptedBarcodesFromRow(r);
        if (aliases.isNotEmpty) {
          _itemBarcodeAliasesByItemId[id] = aliases;
        }
      }
    }
    _itemRows = normalized;
    itemsApplied = true;
  }

  /// Extra product barcodes from mother (`item_barcodes`), keyed by item id.
  Map<int, List<String>> getItemBarcodeAliasesMap() =>
      Map<int, List<String>>.from(_itemBarcodeAliasesByItemId);

  List<Store> getStores() {
    final list = _storeRows
        .map((m) => Store.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Store? getDefaultStore() {
    for (final m in _storeRows) {
      if ((m['is_default'] as int? ?? 0) == 1) {
        return Store.fromMap(Map<String, dynamic>.from(m));
      }
    }
    return null;
  }

  List<Client> getClients({int? storeId}) {
    var list = _clientRows
        .map((m) => Client.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (storeId != null) {
      list = list.where((c) => c.storeId == storeId).toList();
    }
    list.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return list;
  }

  Client? getClientByNormalizedName(String customerName) {
    final target = customerName.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final c in getClients()) {
      if (c.name.trim().toLowerCase() == target) return c;
    }
    return null;
  }

  List<Item> getItems({int? storeId}) {
    var list = _itemRows
        .map((m) => Item.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (storeId != null) {
      list = list.where((e) => e.storeId == storeId).toList();
    }
    list.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return list;
  }

  List<Item> getReorderItems({int? storeId}) {
    return getItems(storeId: storeId)
        .where(
          (e) =>
              !isMeterSoldFixedStockItemName(e.name) &&
              (e.stockQty <= e.reorderLevel || e.stockQty <= 0),
        )
        .toList();
  }
}
