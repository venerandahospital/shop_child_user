import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'asset_depreciation_screen.dart';
import 'asset_form_screen.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
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
    final assets = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchAssets()
        : await _db.getAssets();
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  Future<void> _openAssetForm({Asset? asset}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssetFormScreen(existing: asset),
      ),
    );
    if (changed == true && mounted) {
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
    if (await _auth.isRemoteUser()) {
      final remote = await _auth.deleteRemoteAsset(asset.id!);
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (remote['message'] ?? 'Failed to delete asset on mother').toString(),
            ),
          ),
        );
        return;
      }
    } else {
      await _db.deleteAsset(asset.id!);
    }
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
                                onPressed: () => _openAssetForm(asset: asset),
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
        heroTag: null,
        onPressed: () => _openAssetForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

