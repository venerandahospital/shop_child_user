import 'package:flutter/material.dart';

import '../models/unit.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';

class UnitManagementScreen extends StatefulWidget {
  const UnitManagementScreen({super.key});

  @override
  State<UnitManagementScreen> createState() => _UnitManagementScreenState();
}

class _UnitManagementScreenState extends State<UnitManagementScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _shortController = TextEditingController();

  List<Unit> _units = [];
  bool _loading = true;
  bool _saving = false;
  Unit? _editingUnit;

  @override
  void initState() {
    super.initState();
    _db.transactionVersion.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    _db.transactionVersion.removeListener(_onDataChanged);
    _nameController.dispose();
    _shortController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final list = isRemote
        ? await RemoteSyncService.instance.fetchUnits()
        : await _db.getUnits();
    if (mounted) {
      setState(() {
        _units = list;
        _loading = false;
      });
    }
  }

  void _clearForm() {
    _nameController.clear();
    _shortController.clear();
    setState(() => _editingUnit = null);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final short = _shortController.text.trim();
    if (name.isEmpty || short.isEmpty) return;

    setState(() => _saving = true);
    try {
      final isRemote = await _auth.isRemoteUser();
      if (_editingUnit != null) {
        if (isRemote) {
          final remote = await _auth.saveRemoteUnit({
            'id': _editingUnit!.id,
            'unit_name': name,
            'unit_short_name': short,
          });
          if (remote['success'] != true) {
            throw StateError((remote['message'] ?? 'Failed to update unit').toString());
          }
        } else {
          await _db.updateUnit(Unit(
            id: _editingUnit!.id,
            unitName: name,
            unitShortName: short,
          ));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unit updated')),
          );
        }
      } else {
        if (isRemote) {
          final remote = await _auth.saveRemoteUnit({
            'unit_name': name,
            'unit_short_name': short,
          });
          if (remote['success'] != true) {
            throw StateError((remote['message'] ?? 'Failed to create unit').toString());
          }
        } else {
          await _db.insertUnit(Unit(unitName: name, unitShortName: short));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unit created')),
          );
        }
      }
      _clearForm();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEdit(Unit unit) {
    _nameController.text = unit.unitName;
    _shortController.text = unit.unitShortName;
    setState(() => _editingUnit = unit);
  }

  Future<void> _delete(Unit unit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unit'),
        content: Text(
          'Delete "${unit.unitName}"? Items using this unit will keep their current unit text.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final isRemote = await _auth.isRemoteUser();
    if (isRemote) {
      final remote = await _auth.deleteRemoteUnit(unit.id!);
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((remote['message'] ?? 'Failed to delete unit').toString())),
        );
        return;
      }
    } else {
      await _db.deleteUnit(unit.id!);
    }
    if (_editingUnit?.id == unit.id) _clearForm();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit deleted')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit Management'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Unit-Name',
                  hintText: 'Enter Unit Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter unit name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortController,
                decoration: const InputDecoration(
                  labelText: 'Unit-Short-Name',
                  hintText: 'Enter Unit Short Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter short name' : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_editingUnit != null ? 'Update Unit' : 'Create Unit'),
                ),
              ),
              if (_editingUnit != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _clearForm,
                  child: const Text('Cancel edit'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Existing Units',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_units.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No units yet. Create one above.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                )
              else
                ..._units.map((unit) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        title: Text(
                          unit.unitName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          unit.unitShortName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.filledTonal(
                              onPressed: () => _startEdit(unit),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () => _delete(unit),
                              icon: const Icon(Icons.delete_outline, size: 20),
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}
