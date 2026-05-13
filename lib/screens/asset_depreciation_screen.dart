import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

class AssetDepreciationScreen extends StatefulWidget {
  const AssetDepreciationScreen({super.key, required this.asset});

  final Asset asset;

  @override
  State<AssetDepreciationScreen> createState() => _AssetDepreciationScreenState();
}

class _AssetDepreciationScreenState extends State<AssetDepreciationScreen> {
  final _db = LocalDbService.instance;
  final _appSettings = AppSettingsService.instance;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _saving = false;
  String _currencySymbol = 'USh';
  Asset? _asset;
  List<Map<String, Object?>> _history = [];

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
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _appSettings.currencySymbol);
  }

  Future<void> _load() async {
    final allAssets = await _db.getAssets();
    final current = allAssets.where((a) => a.id == widget.asset.id).toList();
    final history = await _db.getAssetDepreciations(widget.asset.id!);
    if (!mounted) return;
    setState(() {
      _asset = current.isEmpty ? widget.asset : current.first;
      _history = history;
    });
  }

  Future<void> _applyDepreciation() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0 || widget.asset.id == null) return;
    setState(() => _saving = true);
    await _db.addAssetDepreciation(
      assetId: widget.asset.id!,
      amount: amount,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
    _amountController.clear();
    _noteController.clear();
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
  }

  String _formatDateTime(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset ?? widget.asset;
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Asset depreciation'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    toTitleCaseWords(asset.name),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Purchase: $_currencySymbol${formatMoney(asset.purchaseCost)}',
                  ),
                  Text(
                    'Current: $_currencySymbol${formatMoney(asset.currentValue)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Depreciation amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _applyDepreciation,
            icon: const Icon(Icons.trending_down),
            label: Text(_saving ? 'Saving...' : 'Apply depreciation'),
          ),
          const SizedBox(height: 16),
          Text(
            'Depreciation history',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No depreciation records yet.')),
            )
          else
            ..._history.map((row) {
              final amount = (row['amount'] as num?)?.toDouble() ?? 0;
              final note = (row['note'] ?? '').toString();
              final createdAt =
                  DateTime.tryParse((row['created_at'] ?? '').toString()) ??
                      DateTime.now();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.trending_down, color: Colors.orange),
                  title: Text('- $_currencySymbol${formatMoney(amount)}'),
                  subtitle: Text(
                    '${_formatDateTime(createdAt)}${note.trim().isEmpty ? '' : ' • $note'}',
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
