import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/cart_draft.dart';
import '../services/local_db_service.dart';

class CartDraftsScreen extends StatefulWidget {
  const CartDraftsScreen({super.key});

  @override
  State<CartDraftsScreen> createState() => _CartDraftsScreenState();
}

class _CartDraftsScreenState extends State<CartDraftsScreen> {
  final _db = LocalDbService.instance;
  List<CartDraft> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getCartDrafts();
    if (!mounted) return;
    setState(() {
      _drafts = list;
      _loading = false;
    });
  }

  int _lineCount(CartDraft d) {
    try {
      final m = jsonDecode(d.payloadJson) as Map<String, dynamic>;
      final lines = m['lines'] as List?;
      return lines?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _confirmDelete(CartDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text('Remove "${d.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _db.deleteCartDraft(d.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved cart drafts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No drafts yet.\nSave a cart from the sale page.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _drafts.length,
                  itemBuilder: (context, index) {
                    final d = _drafts[index];
                    final lc = _lineCount(d);
                    return ListTile(
                      title: Text(d.title),
                      subtitle: Text(
                        '$lc line(s) · ${d.updatedAt.toLocal().toString().split('.').first}',
                      ),
                      onTap: () => Navigator.pop(context, d),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(d),
                      ),
                    );
                  },
                ),
    );
  }
}
