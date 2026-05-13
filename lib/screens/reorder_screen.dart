import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';

class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key});

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  bool _loading = true;
  List<Item> _items = [];

  bool _isServiceSaleItem(Item item) {
    final raw = (item.category ?? '').toLowerCase();
    return raw.contains('sale: service');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final items = (isRemote
        ? (await RemoteSyncService.instance.fetchItems())
            .where((item) => item.stockQty <= item.reorderLevel || item.stockQty <= 0)
            .toList()
        : await _db.getReorderItems())
        .where((item) => !_isServiceSaleItem(item))
        .toList();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder'),
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
            : _items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text(
                          'No items need reorder right now.',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final stock = item.stockQty;
                      final level = item.reorderLevel;
                      final restockTo = item.restockTo;
                      final suggested = restockTo > stock
                          ? (restockTo - stock)
                          : (level > stock ? (level - stock) : 0);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
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
                          ),
                          title: Text(toTitleCaseWords(item.name)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stock at hand: ${formatDisplayNumber(stock)} ${item.unit ?? ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Reorder level: ${formatDisplayNumber(level)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (restockTo > 0)
                                Text(
                                  'Restock to: ${formatDisplayNumber(restockTo)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              Text(
                                'Suggested to reorder: ${formatDisplayNumber(suggested)}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
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

