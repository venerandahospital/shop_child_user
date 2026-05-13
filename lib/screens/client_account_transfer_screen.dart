import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';

class ClientAccountTransferScreen extends StatefulWidget {
  const ClientAccountTransferScreen({
    super.key,
    required this.sourceClient,
    required this.sourceBalance,
  });

  final Client sourceClient;
  final double sourceBalance;

  @override
  State<ClientAccountTransferScreen> createState() =>
      _ClientAccountTransferScreenState();
}

class _ClientAccountTransferScreenState extends State<ClientAccountTransferScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _currencySymbol = 'USh';
  List<Client> _targets = [];
  int? _selectedTargetClientId;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadTargets();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  Future<void> _loadTargets() async {
    final isRemote = await _auth.isRemoteUser();
    final clients = isRemote
        ? await RemoteSyncService.instance.fetchClients()
        : await _db.getClients();
    final targets = clients
        .where(
          (c) => c.id != null && c.id != widget.sourceClient.id,
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _targets = targets;
      _selectedTargetClientId = targets.isNotEmpty ? targets.first.id : null;
      _loading = false;
    });
  }

  String _accountNumberForClient(Client client) {
    final id = client.id ?? 0;
    return 'CA-${id.toString().padLeft(6, '0')}';
  }

  Future<void> _submit() async {
    if (_saving) return;
    final targetId = _selectedTargetClientId;
    final amount =
        double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;
    final note = _noteController.text.trim();
    if (targetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose destination account.')),
      );
      return;
    }
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount.')),
      );
      return;
    }
    if (amount > widget.sourceBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient source account balance.')),
      );
      return;
    }
    final target = _targets.firstWhere((c) => c.id == targetId);
    setState(() => _saving = true);
    try {
      final transferNote = note.isEmpty
          ? 'Transfer from ${widget.sourceClient.name} to ${target.name}'
          : note;
      if (await _auth.isRemoteUser()) {
        final withdraw = await _auth.postRemoteClientAccountTransaction(
          clientId: widget.sourceClient.id!,
          amount: -amount,
          transactionType: 'transfer_out',
          note: transferNote,
        );
        if (withdraw['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((withdraw['message'] ?? 'Transfer failed').toString())),
          );
          return;
        }
        final deposit = await _auth.postRemoteClientAccountTransaction(
          clientId: target.id!,
          amount: amount,
          transactionType: 'transfer_in',
          note: transferNote,
        );
        if (deposit['success'] != true) {
          await _auth.postRemoteClientAccountTransaction(
            clientId: widget.sourceClient.id!,
            amount: amount,
            transactionType: 'transfer_reversal',
            note: 'Auto-reversal for failed transfer to ${target.name}',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((deposit['message'] ?? 'Transfer failed').toString())),
          );
          return;
        }
      } else {
        await _db.recordClientAccountTransaction(
          clientId: widget.sourceClient.id!,
          storeId: widget.sourceClient.storeId,
          transactionType: 'transfer_out',
          amount: -amount,
          note: transferNote,
        );
        await _db.recordClientAccountTransaction(
          clientId: target.id!,
          storeId: target.storeId,
          transactionType: 'transfer_in',
          amount: amount,
          note: transferNote,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfer failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.sourceClient;
    final sourceAccount = _accountNumberForClient(source);
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer funds')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'From account',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(source.name.toUpperCase()),
                        const SizedBox(height: 2),
                        Text('Account number: $sourceAccount'),
                        const SizedBox(height: 6),
                        Text(
                          'Balance: $_currencySymbol${formatMoney(widget.sourceBalance)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: _selectedTargetClientId,
                          items: _targets
                              .map(
                                (c) => DropdownMenuItem<int>(
                                  value: c.id!,
                                  child: Text(
                                    '${c.name} (${_accountNumberForClient(c)})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _selectedTargetClientId = v),
                          decoration: const InputDecoration(
                            labelText: 'To account',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            prefixText: '$_currencySymbol ',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ElevatedButton.icon(
          onPressed: _loading || _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.swap_horiz),
          label: Text(_saving ? 'Transferring...' : 'Transfer'),
        ),
      ),
    );
  }
}
