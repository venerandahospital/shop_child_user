import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/cart_draft.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';

class CartDraftsScreen extends StatefulWidget {
  const CartDraftsScreen({super.key});

  @override
  State<CartDraftsScreen> createState() => _CartDraftsScreenState();
}

class _CartDraftsScreenState extends State<CartDraftsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  List<CartDraft> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchCartDrafts()
        : await _db.getCartDrafts();
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
    if (await _auth.isRemoteUser()) {
      final res = await _auth.deleteRemoteCartDraft(d.id);
      if (res['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (res['message'] ?? 'Failed to delete draft on mother').toString(),
            ),
          ),
        );
        return;
      }
    } else {
      await _db.deleteCartDraft(d.id);
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft deleted')),
      );
    }
  }

  Future<void> _confirmDeleteAll() async {
    if (_drafts.isEmpty) return;
    final isRemote = await _auth.isRemoteUser();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all drafts?'),
        content: Text(
          isRemote
              ? 'This will remove all ${_drafts.length} drafts on the mother device.'
              : 'This will remove all ${_drafts.length} saved drafts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (isRemote) {
      final res = await _auth.deleteAllRemoteCartDrafts();
      if (res['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (res['message'] ?? 'Failed to delete drafts on mother').toString(),
            ),
          ),
        );
        return;
      }
    } else {
      await _db.deleteAllCartDrafts();
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All drafts deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved cart drafts'),
        actions: [
          if (_drafts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Delete all drafts',
              onPressed: _confirmDeleteAll,
            ),
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
