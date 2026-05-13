import 'package:flutter/material.dart';

import '../models/product_category.dart';

class CategoryDetailsScreen extends StatelessWidget {
  const CategoryDetailsScreen({
    super.key,
    required this.category,
    required this.allCategories,
  });

  final ProductCategory category;
  final List<ProductCategory> allCategories;

  List<String> _buildCascade() {
    final chain = <String>[category.subCategory];
    var currentParent = category.mainCategory == category.subCategory
        ? null
        : category.mainCategory;

    // Follow parent links upwards if available (supports parent/sub-parent chains).
    while (currentParent != null && currentParent.trim().isNotEmpty) {
      chain.insert(0, currentParent);
      final parentRow = allCategories.where((c) => c.subCategory == currentParent);
      if (parentRow.isEmpty) break;
      final next = parentRow.first.mainCategory;
      if (next == currentParent) break;
      currentParent = next;
    }
    return chain;
  }

  List<String> _directChildren() {
    return allCategories
        .where((c) => c.mainCategory == category.subCategory && c.subCategory != c.mainCategory)
        .map((c) => c.subCategory)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cascade = _buildCascade();
    final children = _directChildren();

    return Scaffold(
      appBar: AppBar(title: const Text('Category details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            category.subCategory,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _Tile(
            label: 'Top level parent',
            value: cascade.isEmpty ? '—' : cascade.first,
          ),
          _Tile(
            label: 'Immediate parent',
            value: category.mainCategory == category.subCategory
                ? 'Top level'
                : category.mainCategory,
          ),
          _Tile(
            label: 'Category cascade',
            value: cascade.join(' > '),
          ),
          _Tile(
            label: 'Direct children',
            value: children.isEmpty ? 'None' : children.join(', '),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(value)),
        ],
      ),
    );
  }
}

