import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import 'receive_stock_screen.dart';

class StockReceiptsListScreen extends StatefulWidget {
  const StockReceiptsListScreen({
    super.key,
    this.itemId,
    this.itemName,
    this.adjustmentOnly = false,
  });

  final int? itemId;
  final String? itemName;
  final bool adjustmentOnly;

  @override
  State<StockReceiptsListScreen> createState() => _StockReceiptsListScreenState();
}

class _StockReceiptsListScreenState extends State<StockReceiptsListScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;
  bool _loading = true;
  List<Map<String, Object?>> _rows = [];
  String _currencySymbol = 'USh';

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchStockReceipts()
        : await _db.getStockReceiptsWithDetails();
    final byItem = widget.itemId == null
        ? data
        : data.where((row) => row['item_id'] == widget.itemId).toList();
    final filtered = widget.adjustmentOnly
        ? byItem.where((row) {
            final brand = (row['brand'] ?? '').toString().trim();
            return brand.startsWith('ADJ|');
          }).toList()
        : byItem;
    if (!mounted) return;
    setState(() {
      _rows = filtered;
      _loading = false;
    });
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.itemName == null || widget.itemName!.trim().isEmpty
        ? (widget.adjustmentOnly ? 'Stock adjustments' : 'Receive records')
        : '${toTitleCaseWords(widget.itemName!.trim())} records';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('No receive records yet. Receive stock from the Receive stock page.'),
                      ),
                    ],
                  )
                : Builder(
                    builder: (context) {
                      final grouped = <String, List<Map<String, Object?>>>{};
                      for (final row in _rows) {
                        final receivedAt = row['received_at'] as String? ?? '';
                        final dt = DateTime.tryParse(receivedAt);
                        final dayKey = dt == null
                            ? 'Unknown date'
                            : '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                        grouped.putIfAbsent(dayKey, () => []).add(row);
                      }

                      return ListView(
                        padding: const EdgeInsets.all(12),
                        children: grouped.entries.map((entry) {
                          final day = entry.key;
                          final dayRows = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    day,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...dayRows.map((row) {
                                    final receivedAt = row['received_at'] as String?;
                                    final itemName = toTitleCaseWords((row['item_name'] as String?) ?? '—');
                                    final qty =
                                        (row['quantity'] as num?)?.toDouble() ?? 0;
                                    final oldQty =
                                        (row['old_qty'] as num?)?.toDouble() ?? 0;
                                    final newQty =
                                        (row['new_qty'] as num?)?.toDouble() ?? 0;
                                    final brand = (row['brand'] ?? '').toString().trim();
                                    final isAdjustment = brand.startsWith('ADJ|');
                                    final reason = isAdjustment
                                        ? brand.substring(4).trim()
                                        : '';
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 4,
                                      ),
                                      title: Text(
                                        itemName,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${isAdjustment ? 'Quantity adjusted' : 'Quantity received'}: ${formatDisplayNumber(qty)}',
                                          ),
                                          Text(
                                            'Previous quantity: ${formatDisplayNumber(oldQty)}',
                                          ),
                                          Text(
                                            'New quantity: ${formatDisplayNumber(newQty)}',
                                          ),
                                          Text(
                                            'Receive date: ${_formatDate(receivedAt)}',
                                          ),
                                          if (isAdjustment && reason.isNotEmpty)
                                            Text('Reason: $reason'),
                                        ],
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                _StockReceiptDetailsScreen(
                                              row: row,
                                              currencySymbol: _currencySymbol,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
      ),
      floatingActionButton: widget.adjustmentOnly
          ? null
          : FloatingActionButton(
              tooltip: 'Receive stock',
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ReceiveStockScreen(initialItemId: widget.itemId),
                  ),
                );
                if (changed == true) {
                  await _load();
                }
              },
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _StockReceiptDetailsScreen extends StatelessWidget {
  const _StockReceiptDetailsScreen({
    required this.row,
    required this.currencySymbol,
  });

  final Map<String, Object?> row;
  final String currencySymbol;

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateOnly(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final itemName = toTitleCaseWords((row['item_name'] as String?) ?? '—');
    final expiry = row['expiry_date'] as String?;
    final receivedAt = row['received_at'] as String?;
    final totalCost = (row['total_cost'] as num?)?.toDouble() ?? 0;
    final unitCost = (row['unit_cost'] as num?)?.toDouble() ?? 0;
    final unitSell = (row['unit_sell'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive record details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            itemName,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _DetailTile(label: 'Expiry date', value: _formatDateOnly(expiry)),
          _DetailTile(
            label: 'Total cost',
            value: '$currencySymbol${formatMoney(totalCost)}',
          ),
          _DetailTile(
            label: 'Unit cost',
            value: '$currencySymbol${formatMoney(unitCost)}',
          ),
          _DetailTile(label: 'Receive date', value: _formatDate(receivedAt)),
          _DetailTile(
            label: 'Unit sell',
            value: '$currencySymbol${formatMoney(unitSell)}',
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
