import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/transactions_service.dart';
import '../navigation/app_router.dart';

class ChildTransactionsScreen extends StatefulWidget {
  const ChildTransactionsScreen({super.key});

  @override
  State<ChildTransactionsScreen> createState() =>
      _ChildTransactionsScreenState();
}

class _ChildTransactionsScreenState extends State<ChildTransactionsScreen> {
  final _transactions = TransactionsService();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _transactions.fetchTransactions();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_description.text.trim().isEmpty || amount == null) return;
    final ok = await _transactions.createTransaction(
      description: _description.text.trim(),
      amount: amount,
    );
    if (!mounted) return;
    if (ok) {
      _description.clear();
      _amount.clear();
      await _load();
    }
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRouter.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRouter.connect),
            icon: const Icon(Icons.wifi),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ),
                IconButton(onPressed: _submit, icon: const Icon(Icons.send)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return ListTile(
                        title: Text((row['description'] ?? '').toString()),
                        subtitle: Text((row['user_email'] ?? '').toString()),
                        trailing: Text((row['amount'] ?? '').toString()),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
