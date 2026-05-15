import 'package:flutter/material.dart';

import '../services/special_items_service.dart';
import '../utils/meter_fixed_stock_items.dart';
import '../widgets/section_page_title.dart';

/// Manage extra product names treated as special roll items.
class SpecialItemsScreen extends StatefulWidget {
  const SpecialItemsScreen({super.key});

  @override
  State<SpecialItemsScreen> createState() => _SpecialItemsScreenState();
}

class _SpecialItemsScreenState extends State<SpecialItemsScreen> {
  final _patternController = TextEditingController();
  List<String> _extras = const [];
  bool _loading = true;

  static const _builtInLabels = <String>[
    'Ekiveera white / black (name contains ekiveera + white or black)',
    'Carpet (name contains carpet)',
    'Ebinyobwa (name contains ebinyobwa)',
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await SpecialItemsService.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _extras = SpecialItemsService.instance.extraPatterns;
      _loading = false;
    });
  }

  Future<void> _addPattern() async {
    final p = _patternController.text.trim();
    if (p.isEmpty) return;
    await SpecialItemsService.instance.addPattern(p);
    _patternController.clear();
    await _reload();
  }

  Future<void> _removePattern(String pattern) async {
    await SpecialItemsService.instance.removePattern(pattern);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Special items'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Special items use stock 0 or 1, availability check at sale, '
                  'and roll metres tracked separately. Built-in name rules cannot be removed.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('Built-in rules', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ..._builtInLabels.map(
                  (label) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.lock_outline, size: 20),
                    title: Text(label),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Additional name patterns', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_extras.isEmpty)
                  Text(
                    'No extra patterns. Add a word that appears in the product name.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ..._extras.map(
                  (p) => Card(
                    child: ListTile(
                      title: Text(p),
                      subtitle: Text(
                        isMeterSoldFixedStockItemName('sample $p item')
                            ? 'Matches names containing "$p"'
                            : 'Pattern active after save',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removePattern(p),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _patternController,
                        decoration: const InputDecoration(
                          labelText: 'Name contains…',
                          hintText: 'e.g. polythene',
                        ),
                        onSubmitted: (_) => _addPattern(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addPattern,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
