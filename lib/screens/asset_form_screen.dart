import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';

/// Full-screen form for creating or editing an asset (avoids dialog lifecycle
/// issues with [TextEditingController]s and nested routes like date picker).
class AssetFormScreen extends StatefulWidget {
  const AssetFormScreen({super.key, this.existing});

  final Asset? existing;

  @override
  State<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends State<AssetFormScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;

  late final TextEditingController _nameController;
  late final TextEditingController _purchaseCostController;
  late final TextEditingController _currentValueController;
  late final TextEditingController _notesController;
  late DateTime _purchaseDate;

  bool _saving = false;
  String _currencySymbol = 'USh';

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _nameController = TextEditingController(text: a?.name ?? '');
    _purchaseCostController = TextEditingController(
      text: a == null ? '' : formatDisplayNumber(a.purchaseCost),
    );
    _currentValueController = TextEditingController(
      text: a == null ? '' : formatDisplayNumber(a.currentValue),
    );
    _notesController = TextEditingController(text: a?.notes ?? '');
    _purchaseDate = a?.purchaseDate ?? DateTime.now();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _nameController.dispose();
    _purchaseCostController.dispose();
    _currentValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) {
      setState(() => _purchaseDate = picked);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an asset name')),
      );
      return;
    }
    final purchaseCost = double.tryParse(
          _purchaseCostController.text.replaceAll(',', '.'),
        ) ??
        0;
    final currentValue = double.tryParse(
          _currentValueController.text.replaceAll(',', '.'),
        ) ??
        0;
    final effectiveCurrent = currentValue <= 0 ? purchaseCost : currentValue;

    setState(() => _saving = true);
    try {
      final asset = Asset(
        id: widget.existing?.id,
        storeId: widget.existing?.storeId,
        name: name,
        purchaseCost: purchaseCost,
        currentValue: effectiveCurrent,
        purchaseDate: _purchaseDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: widget.existing?.createdAt,
      );
      if (await _auth.isRemoteUser()) {
        final remote = await _auth.saveRemoteAsset(asset.toMap());
        if (remote['success'] != true) {
          throw Exception((remote['message'] ?? 'Failed to sync asset').toString());
        }
      } else {
        await _db.upsertAsset(asset);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save asset: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.existing == null;

    return Scaffold(
      appBar: AppBar(
        title: SectionPageTitle(
          pageTitle: isNew ? 'New asset' : 'Edit asset',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Amounts in $_currencySymbol',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Asset name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purchaseCostController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Purchase cost',
              prefixText: '$_currencySymbol ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currentValueController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Current value',
              prefixText: '$_currencySymbol ',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase date'),
            subtitle: Text(_formatDate(_purchaseDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: _saving ? null : _pickDate,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
