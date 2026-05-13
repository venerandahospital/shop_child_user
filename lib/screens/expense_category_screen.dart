import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../services/local_db_service.dart';

class ExpenseCategoryScreen extends StatefulWidget {
  const ExpenseCategoryScreen({super.key});

  @override
  State<ExpenseCategoryScreen> createState() => _ExpenseCategoryScreenState();
}

class _ExpenseCategoryScreenState extends State<ExpenseCategoryScreen> {
  final _db = LocalDbService.instance;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  List<ExpenseCategory> _categories = [];
  bool _loading = true;
  bool _saving = false;
  ExpenseCategory? _editing;
  int? _selectedParentId;

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
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getExpenseCategoriesWithPath();
    if (mounted) {
      setState(() {
        _categories = list;
        _loading = false;
      });
    }
  }

  void _clearForm() {
    _nameController.clear();
    setState(() {
      _editing = null;
      _selectedParentId = null;
    });
  }

  List<ExpenseCategory> get _parentOptions {
    return _db.excludeSelfAndDescendants(_categories, _editing?.id);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      if (_editing != null) {
        await _db.updateExpenseCategory(ExpenseCategory(
          id: _editing!.id,
          name: name,
          parentId: _selectedParentId,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category updated')),
          );
        }
      } else {
        await _db.insertExpenseCategory(ExpenseCategory(
          name: name,
          parentId: _selectedParentId,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category created')),
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

  void _startEdit(ExpenseCategory cat) {
    _nameController.text = cat.name;
    setState(() {
      _editing = cat;
      _selectedParentId = cat.parentId;
    });
  }

  Future<void> _delete(ExpenseCategory cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category'),
        content: Text(
          'Delete "${cat.displayLabel}"? Child categories will become top-level. Expenses using this category will keep their current category text.',
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
    await _db.deleteExpenseCategory(cat.id!);
    if (_editing?.id == cat.id) _clearForm();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category deleted')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Category'),
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
                  labelText: 'Category',
                  hintText: 'Enter Category',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter category' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _selectedParentId,
                decoration: const InputDecoration(
                  labelText: 'Parent category',
                  hintText: 'None (top-level)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('None (top-level)'),
                  ),
                  ..._parentOptions.map((c) => DropdownMenuItem<int>(
                        value: c.id,
                        child: Text(c.displayLabel),
                      )),
                ],
                onChanged: (value) {
                  setState(() => _selectedParentId = value);
                },
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
                      : Text(_editing != null ? 'Update Category' : 'Create Category'),
                ),
              ),
              if (_editing != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _clearForm,
                  child: const Text('Cancel edit'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Expense Categories',
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
              else if (_categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No categories yet. Create one above.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                )
              else
                ..._categories.map((cat) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: EdgeInsets.only(
                          left: 16.0 + (cat.depth * 20.0),
                          right: 16,
                          top: 8,
                          bottom: 8,
                        ),
                        title: Text(
                          cat.name,
                          style: TextStyle(
                            fontWeight: cat.parentId == null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: cat.path != null && cat.path != cat.name
                            ? Text(
                                cat.path!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.filledTonal(
                              onPressed: () => _startEdit(cat),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () => _delete(cat),
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
