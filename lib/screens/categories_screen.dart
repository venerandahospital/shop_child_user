import 'package:flutter/material.dart';

import '../models/product_category.dart';
import 'category_details_screen.dart';
import '../services/local_db_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _db = LocalDbService.instance;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  List<ProductCategory> _categories = [];
  String? _selectedParentName;
  bool _loading = true;
  bool _creating = false;
  ProductCategory? _editingCategory;

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
    final categories = await _db.getCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _loading = false;
      });
    }
  }

  List<String> get _allCategoryNames {
    final names = <String>{};
    for (final c in _categories) {
      if (c.mainCategory.trim().isNotEmpty) names.add(c.mainCategory.trim());
      if (c.subCategory.trim().isNotEmpty) names.add(c.subCategory.trim());
    }
    final list = names.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  Future<void> _createCategory() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final parent = _selectedParentName?.trim();
    final main = (parent == null || parent.isEmpty) ? name : parent;
    final sub = name;
    final wasEditing = _editingCategory != null;

    setState(() => _creating = true);
    try {
      if (_editingCategory != null) {
        await _db.updateCategory(
          ProductCategory(
            id: _editingCategory!.id,
            mainCategory: main,
            subCategory: sub,
          ),
        );
      } else {
        await _db.insertCategory(
          ProductCategory(
            mainCategory: main,
            subCategory: sub,
          ),
        );
      }
      _nameController.clear();
      _selectedParentName = null;
      _editingCategory = null;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasEditing ? 'Category updated' : 'Category created',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _editCategory(ProductCategory category) {
    _nameController.text = category.subCategory;
    _selectedParentName =
        category.mainCategory == category.subCategory ? null : category.mainCategory;
    setState(() => _editingCategory = category);
  }

  void _clearForm() {
    _nameController.clear();
    _selectedParentName = null;
    setState(() => _editingCategory = null);
  }

  Future<void> _deleteCategory(ProductCategory category) async {
    final id = category.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete "${category.subCategory}"?',
        ),
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
    await _db.deleteCategoryById(id);
    if (_editingCategory?.id == id) {
      _clearForm();
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category'),
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
                  labelText: 'Category name',
                  hintText: 'Enter category name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter category name' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _selectedParentName,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Parent category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None (top level category)'),
                  ),
                  ..._allCategoryNames.map(
                    (name) => DropdownMenuItem<String?>(
                      value: name,
                      child: Text(name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedParentName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _creating ? null : _createCategory,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _creating
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _editingCategory != null
                              ? 'Update Category'
                              : 'Create Category',
                        ),
                ),
              ),
              if (_editingCategory != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _clearForm,
                  child: const Text('Cancel edit'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Products Category',
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
                ..._categories.map((category) {
                  final immediateParent = category.mainCategory == category.subCategory
                      ? 'Top level'
                      : category.mainCategory;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(
                        category.subCategory,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Parent: $immediateParent',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CategoryDetailsScreen(
                              category: category,
                              allCategories: _categories,
                            ),
                          ),
                        );
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
                            onPressed: () => _editCategory(category),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            onPressed: () => _deleteCategory(category),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
