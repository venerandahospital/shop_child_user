import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/debt.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';
import 'client_details_screen.dart';
import 'debt_payments_screen.dart';

enum _DebtsQuickRange { today, lastWeek, lastMonth, all }

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  List<Debt> _allDebts = [];
  List<Map<String, Object?>> _clientDebts = [];
  String _currencySymbol = 'USh';
  _DebtsQuickRange _quickRange = _DebtsQuickRange.all;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadDebts();
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  bool _inQuickRange(DateTime createdAt) {
    if (_quickRange == _DebtsQuickRange.all) return true;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    late final DateTime start;
    switch (_quickRange) {
      case _DebtsQuickRange.today:
        start = startOfToday;
        break;
      case _DebtsQuickRange.lastWeek:
        start = startOfToday.subtract(const Duration(days: 6));
        break;
      case _DebtsQuickRange.lastMonth:
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case _DebtsQuickRange.all:
        start = DateTime(2000);
        break;
    }
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return !createdAt.isBefore(start) && !createdAt.isAfter(end);
  }

  List<Map<String, Object?>> _aggregateClientDebts(List<Debt> debts) {
    final clientDebts = <String, Map<String, Object?>>{};
    for (final debt in debts) {
      if (!_inQuickRange(debt.createdAt)) continue;
      final key = debt.customerName.trim().toLowerCase();
      final existing = clientDebts[key];
      if (existing == null) {
        clientDebts[key] = {
          'customer_name': debt.customerName.trim(),
          'phone': debt.phone,
          'address': debt.address,
          'amount': debt.amount,
          'entries': 1,
          'oldest_date': debt.createdAt,
        };
      } else {
        existing['amount'] = ((existing['amount'] as double?) ?? 0) + debt.amount;
        existing['entries'] = ((existing['entries'] as int?) ?? 0) + 1;
        final old = existing['oldest_date'] as DateTime?;
        if (old == null || debt.createdAt.isBefore(old)) {
          existing['oldest_date'] = debt.createdAt;
        }
      }
    }
    final list = clientDebts.values.toList();
    list.sort((a, b) => ((b['amount'] as double?) ?? 0).compareTo((a['amount'] as double?) ?? 0));
    return list;
  }

  void _setQuickRange(_DebtsQuickRange range) {
    if (_quickRange == range) return;
    setState(() {
      _quickRange = range;
      _clientDebts = _aggregateClientDebts(_allDebts);
    });
  }

  Future<void> _loadDebts() async {
    setState(() => _loading = true);
    final debts = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchDebts(isPaid: false)
        : await _db.getDebts(isPaid: false);
    final list = _aggregateClientDebts(debts);
    if (!mounted) return;
    setState(() {
      _allDebts = debts;
      _clientDebts = list;
      _loading = false;
    });
  }

  Future<void> _showPayDialog({
    required String customerName,
    required double amountOwed,
  }) async {
    final amountController = TextEditingController();
    final client = await _db.getClientByNormalizedName(customerName);
    final isRemote = await _auth.isRemoteUser();
    double accountBalance = 0;
    if (client?.id != null) {
      if (isRemote) {
        accountBalance =
            (await _auth.fetchRemoteClientAccountBalance(client!.id!)) ?? 0;
      } else {
        accountBalance = await _db.getClientAccountBalance(client!.id!);
      }
    }
    var useClientAccount = false;
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
                if (client?.id != null) ...[
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
                  if (isRemote) {
                    final remote = await _auth.payRemoteDebt(
                      customerName: customerName,
                      amount: payAmount,
                      clientId: client?.id,
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
                            clientId: client!.id!,
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
                  await _loadDebts();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Debts'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DebtPaymentsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
            tooltip: 'Payment history',
          ),
          IconButton(
            onPressed: _loadDebts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDebts,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _clientDebts.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('No active debts'),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _clientDebts.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final overall = _clientDebts.fold<double>(
                          0,
                          (s, v) => s + ((v['amount'] as double?) ?? 0),
                        );
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Today'),
                                      selected: _quickRange == _DebtsQuickRange.today,
                                      onSelected: (_) => _setQuickRange(_DebtsQuickRange.today),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Last week'),
                                      selected: _quickRange == _DebtsQuickRange.lastWeek,
                                      onSelected: (_) => _setQuickRange(_DebtsQuickRange.lastWeek),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Last month'),
                                      selected: _quickRange == _DebtsQuickRange.lastMonth,
                                      onSelected: (_) => _setQuickRange(_DebtsQuickRange.lastMonth),
                                    ),
                                    ChoiceChip(
                                      label: const Text('All'),
                                      selected: _quickRange == _DebtsQuickRange.all,
                                      onSelected: (_) => _setQuickRange(_DebtsQuickRange.all),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Total debts: $_currencySymbol${formatMoney(overall)}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final debt = _clientDebts[index - 1];
                      final customerName = (debt['customer_name'] as String?) ?? 'Client';
                      final amount = (debt['amount'] as double?) ?? 0;
                      final phone = debt['phone'] as String?;
                      final address = debt['address'] as String?;
                      final oldestDate = debt['oldest_date'] as DateTime?;
                      final entries = (debt['entries'] as int?) ?? 0;
                      final client = Client(
                        name: customerName,
                        phone: phone?.trim().isEmpty ?? true ? null : phone?.trim(),
                        address: address?.trim().isEmpty ?? true ? null : address?.trim(),
                      );
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClientDetailsScreen(client: client),
                              ),
                            ).then((_) => _loadDebts());
                          },
                          title: Text(customerName.toUpperCase()),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_currencySymbol${formatMoney(amount)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (phone != null && phone.trim().isNotEmpty)
                                Text(
                                  phone,
                                  style: theme.textTheme.bodySmall,
                                ),
                              if (address != null && address.trim().isNotEmpty)
                                Text(
                                  address,
                                  style: theme.textTheme.bodySmall,
                                ),
                              Text(
                                '${entries == 1 ? '1 debt entry' : '$entries debt entries'}'
                                '${oldestDate == null ? '' : '  •  Since ${oldestDate.toLocal().toString().split('.').first}'}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.payments_outlined),
                            tooltip: 'Pay debt',
                            onPressed: amount > 0
                                ? () => _showPayDialog(
                                      customerName: customerName,
                                      amountOwed: amount,
                                    )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

}



