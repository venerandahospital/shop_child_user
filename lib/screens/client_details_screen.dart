import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/debt_payment.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';

class ClientDetailsScreen extends StatefulWidget {
  final Client client;
  const ClientDetailsScreen({super.key, required this.client});

  @override
  State<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends State<ClientDetailsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;
  bool _loading = true;
  String _currencySymbol = 'USh';
  List<Map<String, Object?>> _saleRows = [];
  List<DebtPayment> _payments = [];
  double _currentBalance = 0;
  double _accountBalance = 0;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final sales = isRemote
        ? await RemoteSyncService.instance.fetchSalesByCustomer(widget.client.name)
        : await _db.getSalesWithItemDetailsByCustomer(widget.client.name);
    final payments = isRemote
        ? await RemoteSyncService.instance.fetchDebtPayments(
            customerName: widget.client.name,
          )
        : await _db.getDebtPayments(customerName: widget.client.name);
    final balance = isRemote
        ? (await RemoteSyncService.instance
                .fetchDebts(isPaid: false))
            .where(
              (d) =>
                  d.customerName.trim().toLowerCase() ==
                  widget.client.name.trim().toLowerCase(),
            )
            .fold<double>(0, (sum, d) => sum + d.amount)
        : await _db.getOutstandingDebtForCustomer(widget.client.name);
    final accountBalance = widget.client.id == null
        ? 0.0
        : (isRemote
            ? (await _auth.fetchRemoteClientAccountBalance(widget.client.id!)) ?? 0
            : await _db.getClientAccountBalance(widget.client.id!));
    if (!mounted) return;
    setState(() {
      _saleRows = sales;
      _payments = payments;
      _currentBalance = balance;
      _accountBalance = accountBalance;
      _loading = false;
    });
  }

  Future<void> _showPayDialog() async {
    final amountOwed = _currentBalance;
    if (amountOwed <= 0) return;
    final amountController = TextEditingController();
    var useClientAccount = false;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final entered =
                double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
            final liveBalance = (amountOwed - entered).clamp(0, amountOwed);
            return AlertDialog(
              title: const Text('Pay debt'),
              content: SizedBox(
                width: 361,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Client: ${widget.client.name.toUpperCase()}'),
                    const SizedBox(height: 6),
                    Text('Amount owed: $_currencySymbol${formatMoney(amountOwed)}'),
                    const SizedBox(height: 6),
                    Text(
                      'Account balance: $_currencySymbol${formatMoney(_accountBalance)}',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use client account'),
                      value: useClientAccount,
                      onChanged: (widget.client.id == null || _accountBalance <= 0)
                          ? null
                          : (v) => setDialogState(() => useClientAccount = v ?? false),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount to pay',
                        prefixText: '$_currencySymbol ',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Balance after payment'),
                        Text(
                          '$_currencySymbol${formatMoney(liveBalance)}',
                          style: TextStyle(
                            color: liveBalance <= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
                    final payAmount =
                        double.tryParse(amountController.text.replaceAll(',', '.')) ??
                            0;
                    if (payAmount <= 0 || payAmount > amountOwed) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Enter a valid payment amount')),
                      );
                      return;
                    }
                    if (useClientAccount && payAmount > _accountBalance) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Insufficient client account balance'),
                        ),
                      );
                      return;
                    }
                    final isRemote = await _auth.isRemoteUser();
                    double remaining;
                    if (isRemote) {
                      final remote = await _auth.payRemoteDebt(
                        customerName: widget.client.name,
                        amount: payAmount,
                        clientId: widget.client.id,
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
                              clientId: widget.client.id!,
                              customerName: widget.client.name,
                              paymentAmount: payAmount,
                              storeId: widget.client.storeId,
                            )
                          : await _db.payDebtForCustomer(
                              customerName: widget.client.name,
                              paymentAmount: payAmount,
                            );
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    await _load();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          remaining <= 0
                              ? '${widget.client.name} has fully paid.'
                              : 'New balance: $_currencySymbol${formatMoney(remaining)}',
                        ),
                      ),
                    );
                  },
                  child: const Text('Save payment'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAccountDialog() async {
    if (widget.client.id == null) return;
    final amountController = TextEditingController();
    var action = 'deposit';
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Client account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current balance: $_currencySymbol${formatMoney(_accountBalance)}'),
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
                    clientId: widget.client.id!,
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
                    clientId: widget.client.id!,
                    storeId: widget.client.storeId,
                    transactionType: action,
                    amount: signed,
                  );
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                await _load();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _receiptsBySale {
    final bySale = <int, List<Map<String, Object?>>>{};
    for (final row in _saleRows) {
      final saleId = row['sale_id'] as int?;
      if (saleId == null) continue;
      bySale.putIfAbsent(saleId, () => []).add(row);
    }
    final receipts = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final row in _saleRows) {
      final saleId = row['sale_id'] as int?;
      if (saleId == null || seen.contains(saleId)) continue;
      seen.add(saleId);
      final lines = bySale[saleId] ?? [];
      final first = lines.first;
      receipts.add({
        'sale_id': saleId,
        'created_at': first['created_at'],
        'total_amount': (first['total_amount'] as num?)?.toDouble() ?? 0,
        'amount_received': (first['amount_received'] as num?)?.toDouble() ??
            ((first['total_amount'] as num?)?.toDouble() ?? 0),
        'balance': (first['balance'] as num?)?.toDouble() ?? 0,
        'lines': lines,
      });
    }
    return receipts;
  }

  List<Map<String, dynamic>> get _paymentEvents {
    final events = <Map<String, dynamic>>[];

    for (final receipt in _receiptsBySale) {
      final amountReceived = (receipt['amount_received'] as double?) ?? 0;
      if (amountReceived <= 0) continue;
      events.add({
        'kind': 'initial',
        'amount': amountReceived,
        'date': receipt['created_at'] as String?,
        'label': 'Initial payment',
        'reference': 'Receipt #${receipt['sale_id']}',
      });
    }

    for (final payment in _payments) {
      events.add({
        'kind': 'debt',
        'amount': payment.paidAmount,
        'date': payment.createdAt.toIso8601String(),
        'label': 'Debt payment',
        'reference': 'Payment record',
      });
    }

    events.sort((a, b) {
      final aDate = DateTime.tryParse((a['date'] as String?) ?? '') ?? DateTime(1970);
      final bDate = DateTime.tryParse((b['date'] as String?) ?? '') ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return events;
  }

  List<Map<String, dynamic>> get _debtedReceipts {
    return _receiptsBySale
        .where((r) => ((r['balance'] as double?) ?? 0) > 0)
        .toList();
  }

  List<Map<String, dynamic>> get _fullyPaidReceipts {
    return _receiptsBySale
        .where((r) => ((r['balance'] as double?) ?? 0) <= 0)
        .toList();
  }

  Widget _moneyRow(
    String label,
    double amount, {
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: weight,
          ),
        ),
        Text(
          '$_currencySymbol${formatMoney(amount)}',
          style: TextStyle(
            color: color,
            fontWeight: weight,
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersReceiptList(
    ThemeData theme,
    List<Map<String, dynamic>> receipts, {
    required String emptyText,
    bool forceFullyPaid = false,
  }) {
    if (receipts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const SizedBox(height: 80),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(emptyText),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...receipts.map((r) {
          final lines = (r['lines'] as List<Map<String, Object?>>);
          final total = (r['total_amount'] as double?) ?? 0;
          final paidAmount = forceFullyPaid
              ? total
              : ((r['amount_received'] as double?) ?? 0);
          final balance = forceFullyPaid ? 0.0 : ((r['balance'] as double?) ?? 0);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Receipt total: $_currencySymbol${formatMoney(total)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Receipt #${r['sale_id']}  •  ${_fmtDate(r['created_at'] as String?)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Divider(height: 16),
                  ...lines.map((row) {
                    final name = toTitleCaseWords(
                      (row['item_name'] as String?) ?? 'Item',
                    );
                    final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
                    final unit = (row['item_unit'] as String?) ?? '';
                    final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('$name • ${formatDisplayNumber(qty)} $unit'),
                          ),
                          Text('$_currencySymbol${formatMoney(lineTotal)}'),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16),
                  _moneyRow('Total', total),
                  _moneyRow(
                    'Amount paid',
                    paidAmount,
                    color: Colors.green,
                  ),
                  _moneyRow(
                    'Balance',
                    balance,
                    color: balance > 0 ? Colors.red : Colors.green,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.client.name.toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.client.name.toUpperCase(),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.payments_outlined),
                                  tooltip: 'Pay debt',
                                  onPressed:
                                      _currentBalance > 0 ? _showPayDialog : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.account_balance_wallet_outlined),
                                  tooltip: 'Deposit / withdraw',
                                  onPressed: widget.client.id == null ? null : _showAccountDialog,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _moneyRow(
                              'Total amount',
                              _receiptsBySale.fold<double>(
                                0,
                                (sum, r) => sum + ((r['total_amount'] as double?) ?? 0),
                              ),
                              color: Colors.black87,
                            ),
                            const SizedBox(height: 2),
                            _moneyRow(
                              'Total amount paid',
                              _receiptsBySale.fold<double>(
                                0,
                                (sum, r) => sum + ((r['amount_received'] as double?) ?? 0),
                              ) +
                                  _payments.fold<double>(0, (s, p) => s + p.paidAmount),
                              color: Colors.green,
                            ),
                            const SizedBox(height: 2),
                            _moneyRow(
                              'Total balance',
                              _currentBalance,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 2),
                            _moneyRow(
                              'Account balance',
                              _accountBalance,
                              color: Colors.green.shade700,
                            ),
                            if ((widget.client.phone ?? '').trim().isNotEmpty)
                              Text(widget.client.phone!),
                            if ((widget.client.address ?? '').trim().isNotEmpty)
                              Text(widget.client.address!),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Debt orders'),
                      Tab(text: 'Payments'),
                      Tab(text: 'Paid orders'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: Builder(
                            builder: (context) {
                              return _buildOrdersReceiptList(
                                theme,
                                _debtedReceipts,
                                emptyText: 'No debted orders for this client.',
                              );
                            },
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: Builder(
                            builder: (context) {
                              final events = _paymentEvents;
                              if (events.isEmpty) {
                                return ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: const [
                                    SizedBox(height: 80),
                                    Card(
                                      child: Padding(
                                        padding: EdgeInsets.all(14),
                                        child: Text('No payments found for this client yet.'),
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: events.length,
                                itemBuilder: (context, index) {
                                  final e = events[index];
                                  final amount = (e['amount'] as double?) ?? 0;
                                  final label = (e['label'] as String?) ?? 'Payment';
                                  final reference = (e['reference'] as String?) ?? '';
                                  final date = _fmtDate(e['date'] as String?);
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      leading: const Icon(Icons.payments_outlined),
                                      title: Text(label),
                                      subtitle: Text('$reference  •  $date'),
                                      trailing: Text(
                                        '$_currencySymbol${formatMoney(amount)}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: Colors.green[700],
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: Builder(
                            builder: (context) {
                              return _buildOrdersReceiptList(
                                theme,
                                _fullyPaidReceipts,
                                emptyText: 'No fully paid orders yet.',
                                forceFullyPaid: true,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

