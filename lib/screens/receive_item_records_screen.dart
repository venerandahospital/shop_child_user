import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';

class ReceiveItemRecordsScreen extends StatefulWidget {
  const ReceiveItemRecordsScreen({super.key, required this.item});

  final Item item;

  @override
  State<ReceiveItemRecordsScreen> createState() => _ReceiveItemRecordsScreenState();
}

class _ReceiveItemRecordsScreenState extends State<ReceiveItemRecordsScreen> {
  final _db = LocalDbService.instance;
  bool _loading = true;
  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getStockReceiptsForItemWithDetails(widget.item.id!);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateOnly(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${toTitleCaseWords(widget.item.name)} receive records'),
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
                      Center(child: Text('No receive records for this item yet.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
                      final oldQty = (row['old_qty'] as num?)?.toDouble() ?? 0;
                      final newQty = (row['new_qty'] as num?)?.toDouble() ?? 0;
                      final unitCost =
                          (row['unit_cost'] as num?)?.toDouble() ?? 0;
                      final unitSell =
                          (row['unit_sell'] as num?)?.toDouble() ?? 0;
                      final expiry = row['expiry_date'] as String?;
                      final receivedAt = row['received_at'] as String?;
                      final brand = (row['brand'] as String?)?.trim();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Qty received: ${formatDisplayNumber(qty)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                'Previous qty: ${formatDisplayNumber(oldQty)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'New qty: ${formatDisplayNumber(newQty)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Expiry date: ${_formatDateOnly(expiry)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Receive date: ${_formatDateTime(receivedAt)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Brand: ${brand == null || brand.isEmpty ? '—' : brand}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Unit cost: ${formatMoney(unitCost)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Unit sell: ${formatMoney(unitSell)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

