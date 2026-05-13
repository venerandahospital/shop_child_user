import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'asset_depreciation_screen.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final _db = LocalDbService.instance;
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  String _currencySymbol = 'USh';
  List<Asset> _assets = [];

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final assets = await _db.getAssets();
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  Future<void> _showAssetDialog({Asset? asset}) async {
    final nameController = TextEditingController(text: asset?.name ?? '');
    final purchaseCostController = TextEditingController(
      text: asset == null ? '' : asset.purchaseCost.toString(),
    );
    final currentValueController = TextEditingController(
      text: asset == null ? '' : asset.currentValue.toString(),
    );
    final notesController = TextEditingController(text: asset?.notes ?? '');
    DateTime selectedDate = asset?.purchaseDate ?? DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(asset == null ? 'Add asset' : 'Edit asset'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Asset name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: purchaseCostController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Purchase cost'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: currentValueController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Current value'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Purchase date'),
                  subtitle: Text(_formatDate(selectedDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) {
                      setLocalState(() => selectedDate = picked);
                    }
                  },
                ),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final purchaseCost =
                    double.tryParse(purchaseCostController.text.trim()) ?? 0;
                final currentValue =
                    double.tryParse(currentValueController.text.trim()) ?? 0;
                if (name.isEmpty) return;
                await _db.upsertAsset(
                  Asset(
                    id: asset?.id,
                    storeId: asset?.storeId,
                    name: name,
                    purchaseCost: purchaseCost,
                    currentValue: currentValue <= 0 ? purchaseCost : currentValue,
                    purchaseDate: selectedDate,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                    createdAt: asset?.createdAt,
                  ),
                );
                if (!mounted) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    purchaseCostController.dispose();
    currentValueController.dispose();
    notesController.dispose();

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _deleteAsset(Asset asset) async {
    if (asset.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text('Delete "${toTitleCaseWords(asset.name)}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteAsset(asset.id!);
    await _load();
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Assets page'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _assets.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No assets yet. Add your first asset.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text(
                            toTitleCaseWords(asset.name),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Purchase: $_currencySymbol${formatMoney(asset.purchaseCost)} • '
                            'Current: $_currencySymbol${formatMoney(asset.currentValue)}\n'
                            'Date: ${_formatDate(asset.purchaseDate)}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.trending_down),
                                tooltip: 'Depreciation',
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AssetDepreciationScreen(asset: asset),
                                    ),
                                  );
                                  await _load();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _showAssetDialog(asset: asset),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _deleteAsset(asset),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAssetDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
