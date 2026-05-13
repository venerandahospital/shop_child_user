import 'dart:async';

// Pulls business data from the mother's HTTP API (the child has no backend of its
// own) and refreshes [MotherDataCache] so the UI reads mother state in memory.
import 'auth_service.dart';
import 'mother_data_cache.dart';
import '../models/client.dart';
import '../models/debt.dart';
import '../models/debt_payment.dart';
import '../models/expense.dart';
import '../models/item.dart';
import '../models/store.dart';
import '../models/unit.dart';

/// Queued HTTP pulls from the **mother** app (server). The child is a frontend only;
/// mutations go through [AuthService] POST/PUT to the same base URL.
class RemoteSyncService {
  RemoteSyncService._();

  static final RemoteSyncService instance = RemoteSyncService._();

  final _auth = AuthService();
  Future<void> _syncQueue = Future<void>.value();

  Future<T> _runQueued<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _syncQueue = _syncQueue.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<(bool ok, String message)> syncCoreBusinessData() async {
    return _runQueued(() async {
      if (!await _auth.isRemoteUser()) {
        return (true, 'Local user: remote sync skipped.');
      }

      final storesRes = await _auth.getRemoteAuthorized(path: '/stores');
      if (storesRes['success'] != true) {
        return (
          false,
          (storesRes['message'] ?? 'Failed to pull stores from mother.').toString(),
        );
      }

      final clientsRes = await _auth.getRemoteAuthorized(path: '/clients');
      if (clientsRes['success'] != true) {
        return (
          false,
          (clientsRes['message'] ?? 'Failed to pull clients from mother.').toString(),
        );
      }

      final itemsRes = await _auth.getRemoteAuthorized(path: '/items');
      if (itemsRes['success'] != true) {
        return (
          false,
          (itemsRes['message'] ?? 'Failed to pull items from mother.').toString(),
        );
      }

      final stores = _extractRows(storesRes);
      final clients = _extractRows(clientsRes);
      final items = _extractRows(itemsRes);

      MotherDataCache.instance.applyStoresFromRemote(stores);
      MotherDataCache.instance.applyClientsFromRemote(clients);
      MotherDataCache.instance.applyItemsFromRemote(items);
      return (true, 'Core business data synced from mother.');
    });
  }

  Future<(bool ok, String message)> syncStores() async {
    return _runQueued(() async {
      if (!await _auth.isRemoteUser()) return (true, 'Local user: store sync skipped.');
      final res = await _auth.getRemoteAuthorized(path: '/stores');
      if (res['success'] != true) {
        return (false, (res['message'] ?? 'Failed to pull stores from mother.').toString());
      }
      MotherDataCache.instance.applyStoresFromRemote(_extractRows(res));
      return (true, 'Stores synced from mother.');
    });
  }

  Future<List<Store>> fetchStores() async {
    final res = await _auth.getRemoteAuthorized(path: '/stores');
    if (res['success'] != true) return <Store>[];
    final rows = _extractRows(res);
    MotherDataCache.instance.applyStoresFromRemote(rows);
    return MotherDataCache.instance.getStores();
  }

  Future<List<Client>> fetchClients() async {
    final refreshRes = await _auth.getRemoteAuthorized(path: '/clients/refresh');
    if (refreshRes['success'] == true) {
      final rows = _extractRows(refreshRes);
      MotherDataCache.instance.applyClientsFromRemote(rows);
      return MotherDataCache.instance.getClients();
    }
    final res = await _auth.getRemoteAuthorized(path: '/clients');
    if (res['success'] != true) return <Client>[];
    final rows = _extractRows(res);
    MotherDataCache.instance.applyClientsFromRemote(rows);
    return MotherDataCache.instance.getClients();
  }

  Future<List<Item>> fetchItems() async {
    final res = await _auth.getRemoteAuthorized(path: '/items');
    if (res['success'] != true) return <Item>[];
    final rows = _extractRows(res);
    MotherDataCache.instance.applyItemsFromRemote(rows);
    return MotherDataCache.instance.getItems();
  }

  Future<List<Unit>> fetchUnits() async {
    final res = await _auth.fetchRemoteUnits();
    if (res['success'] != true) return <Unit>[];
    return _extractRows(res).map(Unit.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> fetchSalesHistory({
    DateTime? start,
    DateTime? end,
  }) async {
    final queryParts = <String>[];
    if (start != null) {
      queryParts.add('start=${Uri.encodeQueryComponent(start.toIso8601String())}');
    }
    if (end != null) {
      queryParts.add('end=${Uri.encodeQueryComponent(end.toIso8601String())}');
    }
    final suffix = queryParts.isEmpty ? '' : '?${queryParts.join('&')}';
    final res = await _auth.getRemoteAuthorized(path: '/sales/history$suffix');
    if (res['success'] != true) return <Map<String, Object?>>[];
    return _extractRows(res)
        .map((e) => Map<String, Object?>.from(e))
        .toList();
  }

  Future<List<Map<String, Object?>>> fetchSalesByCustomer(
    String customerName,
  ) async {
    final encoded = Uri.encodeQueryComponent(customerName.trim());
    final res = await _auth.getRemoteAuthorized(
      path: '/sales/by-customer?name=$encoded',
    );
    if (res['success'] != true) return <Map<String, Object?>>[];
    return _extractRows(res)
        .map((e) => Map<String, Object?>.from(e))
        .toList();
  }

  Future<List<Debt>> fetchDebts({bool? isPaid}) async {
    final suffix = isPaid == null ? '' : '?isPaid=${isPaid ? 'true' : 'false'}';
    final res = await _auth.getRemoteAuthorized(path: '/debts$suffix');
    if (res['success'] != true) return <Debt>[];
    return _extractRows(res).map(Debt.fromMap).toList();
  }

  Future<List<DebtPayment>> fetchDebtPayments({String? customerName}) async {
    final name = (customerName ?? '').trim();
    final suffix =
        name.isEmpty ? '' : '?customerName=${Uri.encodeQueryComponent(name)}';
    final res = await _auth.getRemoteAuthorized(path: '/debt-payments$suffix');
    if (res['success'] != true) return <DebtPayment>[];
    return _extractRows(res).map(DebtPayment.fromMap).toList();
  }

  Future<List<Expense>> fetchExpenses() async {
    final res = await _auth.getRemoteAuthorized(path: '/expenses');
    if (res['success'] != true) return <Expense>[];
    return _extractRows(res).map(Expense.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> fetchStockReceipts() async {
    final res = await _auth.getRemoteAuthorized(path: '/stock/receipts');
    if (res['success'] != true) return <Map<String, Object?>>[];
    return _extractRows(res)
        .map((e) => Map<String, Object?>.from(e))
        .toList();
  }

  Future<List<Map<String, Object?>>> fetchStockTransfers() async {
    final res = await _auth.getRemoteAuthorized(path: '/stock/transfers');
    if (res['success'] != true) return <Map<String, Object?>>[];
    return _extractRows(res)
        .map((e) => Map<String, Object?>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> fetchDashboardAnalytics({
    String range = 'today',
  }) async {
    final res = await _auth.fetchRemoteDashboardAnalytics(range: range);
    if (res['success'] != true) return <String, dynamic>{};
    final data = res['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<(bool ok, String message)> syncClients() async {
    return _runQueued(() async {
      if (!await _auth.isRemoteUser()) return (true, 'Local user: client sync skipped.');
      final res = await _auth.getRemoteAuthorized(path: '/clients');
      if (res['success'] != true) {
        return (false, (res['message'] ?? 'Failed to pull clients from mother.').toString());
      }
      MotherDataCache.instance.applyClientsFromRemote(_extractRows(res));
      return (true, 'Clients synced from mother.');
    });
  }

  Future<(bool ok, String message)> syncItems() async {
    return _runQueued(() async {
      if (!await _auth.isRemoteUser()) return (true, 'Local user: item sync skipped.');
      final res = await _auth.getRemoteAuthorized(path: '/items');
      if (res['success'] != true) {
        return (false, (res['message'] ?? 'Failed to pull items from mother.').toString());
      }
      MotherDataCache.instance.applyItemsFromRemote(_extractRows(res));
      return (true, 'Items synced from mother.');
    });
  }

  List<Map<String, dynamic>> _extractRows(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }
}

