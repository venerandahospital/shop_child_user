import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'item_edit_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  String _currencySymbol = 'USh';
  List<Item> _services = [];

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
    setState(() => _currencySymbol = _appSettings.currencySymbol);
  }

  bool _isServiceSaleItem(Item item) {
    final raw = (item.category ?? '').toLowerCase();
    return raw.contains('sale: service');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _authService.isRemoteUser()
        ? await RemoteSyncService.instance.fetchItems()
        : await _db.getItems();
    final services = items.where(_isServiceSaleItem).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _services = services;
      _loading = false;
    });
  }

  Future<void> _openEdit({Item? item}) async {
    final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ItemEditScreen(
              item: item ??
                  Item(
                    name: '',
                    category: 'Sale: Service',
                  ),
            ),
          ),
        ) ??
        false;
    if (changed) await _load();
  }

  Future<void> _delete(Item item) async {
    if (item.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text('Delete "${toTitleCaseWords(item.name)}" permanently?'),
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
    if (await _authService.isRemoteUser()) {
      final remote = await _authService.deleteRemoteItem(item.id!);
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (remote['message'] ?? 'Failed to delete on server').toString(),
            ),
          ),
        );
        return;
      }
    }
    await _db.deleteItem(item.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Services'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _services.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('No service items yet. Add your first service item.'),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _services.length,
                    itemBuilder: (context, index) {
                      final item = _services[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      toTitleCaseWords(item.name),
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if ((item.unit ?? '').trim().isNotEmpty)
                                      Text(
                                        'Unit: ${item.unit!.trim()}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Price: $_currencySymbol${formatMoney(item.sellingPrice)}',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _openEdit(item: item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _delete(item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
    );
  }
}
