import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';

class ItemTransactionsScreen extends StatefulWidget {
  const ItemTransactionsScreen({super.key, required this.item});

  final Item item;

  @override
  State<ItemTransactionsScreen> createState() => _ItemTransactionsScreenState();
}

class _ItemEvent {
  const _ItemEvent({
    required this.type,
    required this.dateTime,
    required this.stockDelta,
    required this.label,
    required this.reference,
    this.stockBefore,
    this.stockAfter,
    this.valueMoved,
  });

  final String type;
  final DateTime dateTime;
  final double stockDelta;
  final String label;
  final String reference;
  final double? stockBefore;
  final double? stockAfter;
  final double? valueMoved;
}

class _ItemTransactionsScreenState extends State<ItemTransactionsScreen> {
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  bool _loading = true;
  String _error = '';
  String _currencySymbol = 'USh';
  List<_ItemEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final token = await _auth.getToken();
    if ((token ?? '').isEmpty) {
      if (!mounted) return;
      setState(() {
        _events = [];
        _loading = false;
        _error =
            'Missing session token. Please sign in to load item transactions from mother.';
      });
      return;
    }
    await _loadRemote();
  }

  Future<bool> _loadRemote() async {
    final itemId = widget.item.id;
    if (itemId == null || itemId <= 0) {
      if (!mounted) return false;
      setState(() {
        _events = [];
        _loading = false;
        _error = 'Invalid item id for remote item transactions.';
      });
      return true;
    }

    final remote = await _auth.fetchRemoteItemTransactions(itemId: itemId);
    if (remote['success'] != true) {
      if (!mounted) return false;
      setState(() {
        _events = [];
        _loading = false;
        _error = (remote['message'] ?? 'Failed to load item transactions.').toString();
      });
      return false;
    }
    final rows = _extractRemoteRows(remote);
    final events = <_ItemEvent>[];
    for (final row in rows) {
      final event = _mapRemoteRowToEvent(row);
      if (event != null) {
        events.add(event);
      }
    }
    events.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    if (!mounted) return false;
    setState(() {
      _events = events;
      _loading = false;
      _error = '';
    });
    return true;
  }

  List<Map<String, dynamic>> _extractRemoteRows(Map<String, dynamic> response) {
    List<Map<String, dynamic>> toRows(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (raw is Map<String, dynamic>) {
        final nested =
            raw['rows'] ?? raw['transactions'] ?? raw['items'] ?? raw['data'];
        if (nested is List) {
          return nested
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return const [];
    }

    final candidates = <dynamic>[
      response['data'],
      response['transactions'],
      response['rows'],
      response['items'],
      response,
    ];
    for (final candidate in candidates) {
      final rows = toRows(candidate);
      if (rows.isNotEmpty) return rows;
    }
    return const <Map<String, dynamic>>[];
  }

  _ItemEvent? _mapRemoteRowToEvent(Map<String, dynamic> row) {
    final dtRaw = row['date'] ??
        row['createdAt'] ??
        row['created_at'] ??
        row['sold_at'] ??
        row['received_at'];
    final dt = DateTime.tryParse((dtRaw ?? '').toString());
    if (dt == null) return null;

    final type = (row['type'] ??
            row['transactionType'] ??
            row['transaction_type'] ??
            row['kind'] ??
            row['movement'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();

    double parseNum(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

    final isTransferIn = type == 'transfer_in' || type == 'in';
    final isTransferOut = type == 'transfer_out' || type == 'out';
    final isAdjustment =
        type == 'adjustment' || type == 'stock_adjustment' || type == 'adjust';
    final isReceive = type == 'receive' || type == 'stock_in';
    final isSale = type == 'sale' || type == 'sold' || type == 'stock_out';

    final resolvedType = isTransferIn
        ? 'transfer_in'
        : isTransferOut
            ? 'transfer_out'
            : isAdjustment
                ? 'adjustment'
                : isReceive
                    ? 'receive'
                    : isSale
                        ? 'sale'
                        : (type.contains('transfer') ? type : 'sale');

    final qty = parseNum(
      row['quantity'] ??
          row['qty'] ??
          row['amount'] ??
          row['units'] ??
          row['delta'] ??
          row['change'] ??
          row['movedQty'] ??
          row['moved_qty'] ??
          row['from_quantity'] ??
          row['to_quantity'],
    );

    final qtyIn = parseNum(row['quantityIn'] ?? row['quantity_in'] ?? row['in']);
    final qtyOut = parseNum(row['quantityOut'] ?? row['quantity_out'] ?? row['out']);

    double magnitude;
    if (resolvedType == 'adjustment') {
      if (qty == 0) return null;
      magnitude = qty;
    } else {
      magnitude = qty > 0 ? qty : (qtyIn > 0 ? qtyIn : qtyOut);
      if (magnitude <= 0) return null;
    }

    final stockDelta = switch (resolvedType) {
      'receive' || 'adjustment' => magnitude,
      'sale' => -magnitude.abs(),
      'transfer_in' => magnitude.abs(),
      'transfer_out' => -magnitude.abs(),
      _ => magnitude,
    };

    final label = (row['label'] ?? row['title'] ?? row['description'] ?? '')
        .toString()
        .trim();
    final refRaw = (row['reference'] ??
            row['ref'] ??
            row['id'] ??
            row['saleId'] ??
            row['sale_id'] ??
            row['receiptId'] ??
            row['receipt_id'] ??
            row['transferId'] ??
            row['transfer_id'] ??
            '-')
        .toString()
        .trim();

    final stockBefore = parseNum(
      row['stockBefore'] ??
          row['stock_before'] ??
          row['beforeStock'] ??
          row['before_stock'],
    );
    final stockAfter = parseNum(
      row['stockAfter'] ??
          row['stock_after'] ??
          row['afterStock'] ??
          row['after_stock'],
    );
    final hasStockRange = stockBefore > 0 || stockAfter > 0;

    final valueMoved = parseNum(
      row['lineTotal'] ??
          row['line_total'] ??
          row['valueMoved'] ??
          row['value_moved'] ??
          row['total'] ??
          row['amountTotal'],
    );

    final resolvedLabel = label.isNotEmpty
        ? label
        : switch (resolvedType) {
            'sale' => 'Sold',
            'transfer_in' => 'Transferred in',
            'transfer_out' => 'Transferred out',
            'adjustment' => 'Stock adjustment',
            'receive' => 'Stock received',
            _ => 'Transaction',
          };

    final resolvedReference = refRaw.toLowerCase().contains('#')
        ? refRaw
        : switch (resolvedType) {
            'sale' => 'Sale #$refRaw',
            'transfer_in' || 'transfer_out' => 'Transfer #$refRaw',
            'adjustment' => 'Adjustment #$refRaw',
            _ => 'Receipt #$refRaw',
          };

    return _ItemEvent(
      type: resolvedType,
      dateTime: dt,
      stockDelta: stockDelta,
      label: resolvedLabel,
      reference: resolvedReference,
      stockBefore: hasStockRange ? stockBefore : null,
      stockAfter: hasStockRange ? stockAfter : null,
      valueMoved: valueMoved > 0 ? valueMoved : null,
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _unitLabel() {
    final u = (widget.item.unit ?? widget.item.unitShort ?? '').trim();
    return u.isEmpty ? 'units' : u;
  }

  String _directionLabel(double stockDelta) {
    if (stockDelta > 0) return 'In';
    if (stockDelta < 0) return 'Out';
    return '—';
  }

  IconData _iconFor(_ItemEvent e) {
    return switch (e.type) {
      'receive' => Icons.move_to_inbox_outlined,
      'adjustment' => Icons.tune_outlined,
      'sale' => Icons.shopping_cart_checkout,
      'transfer_in' || 'transfer_out' => Icons.swap_horiz,
      _ => Icons.receipt_long_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitLabel = _unitLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text('${toTitleCaseWords(widget.item.name)} transactions'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  )
                : _events.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'No stock transactions found for this item yet.',
                            ),
                          ),
                        ],
                      )
                    : Builder(
                        builder: (context) {
                          double runningAfter = widget.item.stockQty;
                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _events.length,
                            itemBuilder: (context, index) {
                              final e = _events[index];
                              final d = e.stockDelta;
                              final isIn = d > 0;
                              final isOut = d < 0;
                              final color = isIn
                                  ? Colors.green
                                  : (isOut ? Colors.red : Colors.grey);
                              final before = e.stockBefore ??
                                  (runningAfter - d);
                              final after = e.stockAfter ?? runningAfter;
                              runningAfter = before;

                              final direction = _directionLabel(d);
                              final qtyText =
                                  '${d >= 0 ? '+' : ''}${formatDisplayNumber(d)} $unitLabel';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            _iconFor(e),
                                            color: color,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.label,
                                                  style: theme.textTheme.titleSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Direction: $direction',
                                                  style: theme.textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: Colors.grey[700],
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            qtyText,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              color: color,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${e.reference}  •  ${_fmtDate(e.dateTime)}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Stock: ${formatDisplayNumber(before)} → ${formatDisplayNumber(after)} $unitLabel',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (isOut) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Value moved: $_currencySymbol${formatMoney(e.valueMoved ?? (d.abs() * widget.item.sellingPrice))}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
      ),
    );
  }
}
