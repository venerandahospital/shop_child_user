import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../widgets/section_page_title.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  bool _loading = true;
  List<Store> _stores = [];

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final stores = isRemote
        ? await RemoteSyncService.instance.fetchStores()
        : await _db.getStores();
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _loading = false;
    });
  }

  Future<void> _addOrEditStore({Store? store}) async {
    final nameController = TextEditingController(text: store?.name ?? '');
    final descriptionController =
        TextEditingController(text: store?.description ?? '');
    bool isDefault = store?.isDefault ?? false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(store == null ? 'New store' : 'Edit store'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Store name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Set as default store'),
                      value: isDefault,
                      onChanged: (value) {
                        setStateDialog(() {
                          isDefault = value ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    final updated = Store(
                      id: store?.id,
                      name: name,
                      description: descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      isDefault: isDefault,
                      createdAt: store?.createdAt,
                    );
                    if (await _auth.isRemoteUser()) {
                      final remote = await _auth.saveRemoteStore({
                        'id': updated.id,
                        'name': updated.name,
                        'description': updated.description,
                        'is_default': updated.isDefault,
                        'created_at': updated.createdAt.toIso8601String(),
                      });
                      if (remote['success'] != true) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text((remote['message'] ?? 'Failed to sync store').toString())),
                        );
                        return;
                      }
                      await _loadStores();
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      return;
                    }
                    await _db.upsertStore(updated);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    await _loadStores();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Stores'),
        actions: [
          IconButton(
            onPressed: _loadStores,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stores.isEmpty
              ? Center(
                  child: Text(
                    'No stores yet.\nAdd your first store.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _stores.length,
                  itemBuilder: (context, index) {
                    final store = _stores[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.storefront,
                          color: store.isDefault
                              ? theme.colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(store.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (store.description != null &&
                                store.description!.isNotEmpty)
                              Text(
                                store.description!,
                                style: theme.textTheme.bodySmall,
                              ),
                            if (store.isDefault)
                              Text(
                                'Default store',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _addOrEditStore(store: store),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditStore(),
        icon: const Icon(Icons.add),
        label: const Text('Add store'),
      ),
    );
  }
}



