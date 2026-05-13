import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';
import 'client_account_screen.dart';
import 'client_details_screen.dart';
import 'pay_debt_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;
  final _searchController = TextEditingController();

  bool _loading = true;
  List<Client> _clients = [];
  Map<String, double> _debtByClientName = {};
  Map<int, double> _accountBalanceByClientId = {};
  String _currencySymbol = 'USh';
  String _searchQuery = '';
  String _key(String? value) => (value ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadClients();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  Future<void> _loadClients() async {
    setState(() => _loading = true);
    try {
      final isRemote = await _auth.isRemoteUser();
      final clients = isRemote
          ? await RemoteSyncService.instance.fetchClients()
          : await _db.getClients();
      final debts = isRemote
          ? await RemoteSyncService.instance.fetchDebts(isPaid: false)
          : await _db.getDebts(isPaid: false);
      final debtByName = <String, double>{};
      for (final debt in debts) {
        final key = _key(debt.customerName);
        debtByName[key] = (debtByName[key] ?? 0) + debt.amount;
      }
      if (!mounted) return;
      final balances = <int, double>{};
      for (final c in clients) {
        if (c.id == null) continue;
        if (isRemote) {
          final value = await _auth.fetchRemoteClientAccountBalance(c.id!);
          balances[c.id!] = value ?? 0;
        } else {
          balances[c.id!] = await _db.getClientAccountBalance(c.id!);
        }
      }
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _debtByClientName = debtByName;
        _accountBalanceByClientId = balances;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load clients: $e')),
      );
    }
  }

  List<Client> get _visibleClients {
    if (_searchQuery.isEmpty) return _clients;
    return _clients.where((client) {
      final name = client.name.toLowerCase();
      final phone = (client.phone ?? '').toLowerCase();
      final address = (client.address ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          address.contains(_searchQuery);
    }).toList();
  }

  Future<void> _showClientDialog({Client? client}) async {
    final nameController = TextEditingController(text: client?.name ?? '');
    final phoneController = TextEditingController(text: client?.phone ?? '');
    final addressController =
        TextEditingController(text: client?.address ?? '');

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(client == null ? 'New client' : 'Edit client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Client name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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
                final newClient = Client(
                  id: client?.id,
                  storeId: client?.storeId,
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );
                try {
                  if (await _auth.isRemoteUser()) {
                    final remote = await _auth.saveRemoteClient({
                      'id': newClient.id,
                      'store_id': newClient.storeId,
                      'name': newClient.name,
                      'phone': newClient.phone,
                      'address': newClient.address,
                      'created_at': newClient.createdAt.toIso8601String(),
                    });
                    if (remote['success'] != true) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text((remote['message'] ?? 'Failed to sync client').toString())),
                      );
                      return;
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    await _loadClients();
                    return;
                  }
                  await _db.upsertClient(newClient);
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _loadClients();
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Failed to save client: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPayDialog({
    required Client client,
    required String customerName,
    required double amountOwed,
  }) async {
    final amountController = TextEditingController();
    var useClientAccount = false;
    final accountBalance = client.id == null
        ? 0.0
        : (_accountBalanceByClientId[client.id!] ?? 0);
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Pay debt'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Client: ${customerName.toUpperCase()}'),
                const SizedBox(height: 6),
                Text(
                  'Amount owed: $_currencySymbol${formatMoney(amountOwed)}',
                ),
                if (client.id != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Account balance: $_currencySymbol${formatMoney(accountBalance)}',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use client account'),
                    value: useClientAccount,
                    onChanged: accountBalance <= 0
                        ? null
                        : (v) => setDialogState(() => useClientAccount = v ?? false),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount to pay',
                    prefixText: '$_currencySymbol ',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final payAmount =
                      double.tryParse(amountController.text.replaceAll(',', '.')) ??
                          0;
                  if (payAmount <= 0 || payAmount > amountOwed) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a valid payment amount'),
                      ),
                    );
                    return;
                  }
                  if (useClientAccount && payAmount > accountBalance) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Insufficient client account balance'),
                      ),
                    );
                    return;
                  }
                  double remaining;
                  if (await _auth.isRemoteUser()) {
                    final remote = await _auth.payRemoteDebt(
                      customerName: customerName,
                      amount: payAmount,
                      clientId: client.id,
                      useClientAccount: useClientAccount,
                    );
                    if (remote['success'] != true) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            (remote['message'] ?? 'Failed to pay debt').toString(),
                          ),
                        ),
                      );
                      return;
                    }
                    remaining = (remote['remaining'] as num?)?.toDouble() ?? 0;
                  } else {
                    remaining = useClientAccount
                        ? await _db.payDebtForCustomerFromClientAccount(
                            clientId: client.id!,
                            customerName: customerName,
                            paymentAmount: payAmount,
                            storeId: client.storeId,
                          )
                        : await _db.payDebtForCustomer(
                            customerName: customerName,
                            paymentAmount: payAmount,
                          );
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _loadClients();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        remaining <= 0
                            ? '$customerName has fully paid.'
                            : 'New balance: $_currencySymbol${formatMoney(remaining)}',
                      ),
                    ),
                  );
                },
                child: const Text('Save payment'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPayDebtPage({
    required Client client,
    required String customerName,
    required double amountOwed,
  }) async {
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PayDebtScreen(
          customerName: customerName,
          amountOwed: amountOwed,
          client: client,
        ),
      ),
    );
    if (msg == null) return;
    if (!mounted) return;
    await _loadClients();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showClientAccountDialog(Client client) async {
    if (client.id == null) return;
    final amountController = TextEditingController();
    var action = 'deposit';
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final balance = _accountBalanceByClientId[client.id!] ?? 0;
          return AlertDialog(
            title: Text('${client.name} account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current balance: $_currencySymbol${formatMoney(balance)}'),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'deposit', label: Text('Deposit')),
                    ButtonSegment(value: 'withdraw', label: Text('Withdraw')),
                  ],
                  selected: {action},
                  onSelectionChanged: (s) => setDialogState(() => action = s.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '$_currencySymbol ',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount =
                      double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
                  if (amount <= 0) return;
                  final signed = action == 'deposit' ? amount : -amount;
                  if (await _auth.isRemoteUser()) {
                    final remote = await _auth.postRemoteClientAccountTransaction(
                      clientId: client.id!,
                      amount: signed,
                      transactionType: action,
                    );
                    if (remote['success'] != true) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            (remote['message'] ?? 'Transaction failed').toString(),
                          ),
                        ),
                      );
                      return;
                    }
                  } else {
                    await _db.recordClientAccountTransaction(
                      clientId: client.id!,
                      storeId: client.storeId,
                      transactionType: action,
                      amount: signed,
                    );
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _loadClients();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Clients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClients,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search clients by name, phone, or address',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _smallStatChip(
                  label: 'Clients',
                  value: '${_clients.length}',
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _smallStatChip(
                  label: 'With debt',
                  value:
                      '${_clients.where((c) => (_debtByClientName[_key(c.name)] ?? 0) > 0).length}',
                  color: Colors.red,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadClients,
              child: _loading
                  ? ListView(
                      children: const [
                        SizedBox(height: 160),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _clients.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text('No clients yet. Add your first client.'),
                            ),
                          ],
                        )
                      : _visibleClients.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text('No clients match your search.'),
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 12),
                              children: _visibleClients.map((client) {
                                final debtAmount =
                                    _debtByClientName[_key(client.name)] ?? 0;
                                final accountBalance = client.id == null
                                    ? 0.0
                                    : (_accountBalanceByClientId[client.id!] ?? 0);
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 1,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ClientDetailsScreen(client: client),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                                            child: Text(
                                              client.name.isNotEmpty
                                                  ? client.name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  client.name.toUpperCase(),
                                                  style: theme.textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                if (client.phone != null &&
                                                    client.phone!.trim().isNotEmpty)
                                                  Text(
                                                    client.phone!,
                                                    style: theme.textTheme.bodySmall,
                                                  ),
                                                if (client.address != null &&
                                                    client.address!.trim().isNotEmpty)
                                                  Text(
                                                    client.address!,
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                if (debtAmount > 0) ...[
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Text(
                                                      'Debt $_currencySymbol${formatMoney(debtAmount)}',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.red,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(999),
                                                  ),
                                                  child: Text(
                                                    'Account $_currencySymbol${formatMoney(accountBalance)}',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: Colors.green.shade800,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit),
                                                onPressed: () => _showClientDialog(client: client),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.payments_outlined),
                                                tooltip: 'Pay debt',
                                                onPressed: debtAmount > 0
                                                    ? () => _openPayDebtPage(
                                                          client: client,
                                                          customerName: client.name,
                                                          amountOwed: debtAmount,
                                                        )
                                                    : null,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.account_balance_wallet_outlined),
                                                tooltip: 'Open account',
                                                onPressed: client.id == null
                                                    ? null
                                                    : () async {
                                                        await Navigator.of(context).push(
                                                          MaterialPageRoute(
                                                            builder: (_) => ClientAccountScreen(
                                                              client: client,
                                                            ),
                                                          ),
                                                        );
                                                        await _loadClients();
                                                      },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showClientDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add client'),
      ),
    );
  }

  Widget _smallStatChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

