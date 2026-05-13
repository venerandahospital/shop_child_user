import 'package:flutter/material.dart';

import '../models/packaging.dart';
import '../services/local_db_service.dart';

class PackagingManagementScreen extends StatefulWidget {
  const PackagingManagementScreen({super.key});

  @override
  State<PackagingManagementScreen> createState() => _PackagingManagementScreenState();
}

class _PackagingManagementScreenState extends State<PackagingManagementScreen> {
  final _db = LocalDbService.instance;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _shortController = TextEditingController();
  List<Packaging> _packagings = [];
  Packaging? _editing;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getPackagings();
    if (!mounted) return;
    setState(() {
      _packagings = rows;
      _loading = false;
    });
  }

  void _startEdit(Packaging row) {
    _nameController.text = row.name;
    _shortController.text = row.shortName ?? '';
    setState(() => _editing = row);
  }

  void _clearForm() {
    _nameController.clear();
    _shortController.clear();
    setState(() => _editing = null);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = Packaging(
      id: _editing?.id,
      name: _nameController.text.trim(),
      shortName: _shortController.text.trim().isEmpty ? null : _shortController.text.trim(),
    );
    if (_editing == null) {
      await _db.insertPackaging(payload);
    } else {
      await _db.updatePackaging(payload);
    }
    if (!mounted) return;
    _clearForm();
    await _load();
    setState(() => _saving = false);
  }

  Future<void> _delete(Packaging row) async {
    if (row.id == null) return;
    await _db.deletePackaging(row.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packaging')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Packaging name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _shortController,
                  decoration: const InputDecoration(labelText: 'Short name (optional)'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_editing == null ? 'Add packaging' : 'Update packaging'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            ..._packagings.map(
              (p) => Card(
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(p.shortName ?? '-'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(onPressed: () => _startEdit(p), icon: const Icon(Icons.edit)),
                      IconButton(
                        onPressed: () => _delete(p),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

