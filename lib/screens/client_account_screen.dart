import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import 'client_account_transfer_screen.dart';
import 'client_loans_screen.dart';

class ClientAccountScreen extends StatefulWidget {
  const ClientAccountScreen({super.key, required this.client});

  final Client client;

  @override
  State<ClientAccountScreen> createState() => _ClientAccountScreenState();
}

class _ClientAccountScreenState extends State<ClientAccountScreen>
    with SingleTickerProviderStateMixin {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  bool _loading = true;
  bool _saving = false;
  double _balance = 0;
  String _currencySymbol = 'USh';
  List<Map<String, Object?>> _transactions = const [];
  late TabController _historyTabController;
  /// When true, account name, number, and balance on the card are masked.
  bool _hideAccountCardDetails = false;
  _HistoryDatePreset _historyDatePreset = _HistoryDatePreset.allTime;
  DateTime? _historySingleDate;
  DateTime? _historyRangeStart;
  DateTime? _historyRangeEnd;

  @override
  void initState() {
    super.initState();
    _historyTabController = TabController(length: 5, vsync: this);
    _historyTabController.addListener(() {
      if (_historyTabController.indexIsChanging) return;
      if (mounted) setState(() {});
    });
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    _historyTabController.dispose();
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  String get _accountNumber {
    final id = widget.client.id ?? 0;
    return 'CA-${id.toString().padLeft(6, '0')}';
  }

  String get _displayAccountName {
    if (!_hideAccountCardDetails) {
      return widget.client.name.toUpperCase();
    }
    final n = widget.client.name.trim().length;
    final len = n.clamp(6, 14);
    return List.filled(len, '•').join();
  }

  String get _displayAccountNumber {
    if (!_hideAccountCardDetails) return _accountNumber;
    return 'CA-••••••';
  }

  String get _displayBalanceOnCard {
    if (_loading) return 'Loading...';
    if (!_hideAccountCardDetails) {
      return '$_currencySymbol${formatMoney(_balance)}';
    }
    return '$_currencySymbol ••••••';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.client.id == null) {
      setState(() {
        _balance = 0;
        _loading = false;
      });
      return;
    }
    final isRemote = await _auth.isRemoteUser();
    final clientId = widget.client.id!;
    final balance = isRemote
        ? (await _auth.fetchRemoteClientAccountBalance(clientId)) ?? 0
        : await _db.getClientAccountBalance(clientId);
    final tx = isRemote
        ? await _auth.fetchRemoteClientAccountTransactions(clientId)
        : await _db.getClientAccountTransactions(clientId);
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _transactions = tx;
      _loading = false;
    });
  }

  String _txTypeKey(Map<String, Object?> row) {
    final raw = row['transaction_type'] ?? row['transactionType'];
    return (raw ?? '').toString().trim().toLowerCase();
  }

  String _txTypeLabel(String key) {
    switch (key) {
      case 'deposit':
        return 'Deposit';
      case 'withdraw':
        return 'Withdraw';
      case 'transfer_out':
        return 'Transfer out';
      case 'transfer_in':
        return 'Transfer in';
      case 'transfer_reversal':
        return 'Transfer reversal';
      case 'debt_payment':
        return 'Debt payment';
      case 'loan_disbursement':
        return 'Loan disbursement';
      case 'account_opened':
        return 'Account opened';
      default:
        if (key.isEmpty) return 'Transaction';
        return key.replaceAll('_', ' ');
    }
  }

  List<Map<String, Object?>> _filteredTransactions(int tabIndex) {
    final all = _transactions;
    switch (tabIndex) {
      case 1:
        return all.where((r) => _txTypeKey(r) == 'deposit').toList();
      case 2:
        return all.where((r) => _txTypeKey(r) == 'withdraw').toList();
      case 3:
        return all.where((r) {
          final t = _txTypeKey(r);
          return t == 'transfer_out' ||
              t == 'transfer_in' ||
              t == 'transfer_reversal';
        }).toList();
      case 4:
        return all.where((r) => _txTypeKey(r) == 'debt_payment').toList();
      default:
        return all;
    }
  }

  DateTime _historyStartOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _historyEndOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  (DateTime start, DateTime end)? _historyDateBounds() {
    final now = DateTime.now();
    switch (_historyDatePreset) {
      case _HistoryDatePreset.allTime:
        return null;
      case _HistoryDatePreset.today:
        final d = _historyStartOfDay(now);
        return (d, _historyEndOfDay(d));
      case _HistoryDatePreset.thisWeek:
        final day = _historyStartOfDay(now);
        final monday =
            day.subtract(Duration(days: day.weekday - DateTime.monday));
        final sunday = monday.add(const Duration(days: 6));
        return (monday, _historyEndOfDay(sunday));
      case _HistoryDatePreset.lastWeek:
        final day = _historyStartOfDay(now);
        final thisMonday =
            day.subtract(Duration(days: day.weekday - DateTime.monday));
        final lastMonday = thisMonday.subtract(const Duration(days: 7));
        final lastSunday = lastMonday.add(const Duration(days: 6));
        return (lastMonday, _historyEndOfDay(lastSunday));
      case _HistoryDatePreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        return (start, _historyEndOfDay(end));
      case _HistoryDatePreset.lastMonth:
        final firstThis = DateTime(now.year, now.month, 1);
        final endLast = firstThis.subtract(const Duration(days: 1));
        final startLast = DateTime(endLast.year, endLast.month, 1);
        return (startLast, _historyEndOfDay(endLast));
      case _HistoryDatePreset.thisYear:
        return (
          DateTime(now.year, 1, 1),
          _historyEndOfDay(DateTime(now.year, 12, 31)),
        );
      case _HistoryDatePreset.lastYear:
        final y = now.year - 1;
        return (
          DateTime(y, 1, 1),
          _historyEndOfDay(DateTime(y, 12, 31)),
        );
      case _HistoryDatePreset.singleDate:
        if (_historySingleDate == null) return null;
        final d = _historyStartOfDay(_historySingleDate!);
        return (d, _historyEndOfDay(d));
      case _HistoryDatePreset.dateRange:
        if (_historyRangeStart == null || _historyRangeEnd == null) {
          return null;
        }
        final a = _historyStartOfDay(_historyRangeStart!);
        final b = _historyStartOfDay(_historyRangeEnd!);
        final start = a.isBefore(b) || a.isAtSameMomentAs(b) ? a : b;
        final end = a.isBefore(b) || a.isAtSameMomentAs(b) ? b : a;
        return (start, _historyEndOfDay(end));
    }
  }

  bool _txMatchesHistoryDateFilter(Map<String, Object?> row) {
    final bounds = _historyDateBounds();
    if (bounds == null) return true;
    final tx = _parseTxDate(row);
    if (tx == null) return false;
    final t = tx.toLocal();
    return !t.isBefore(bounds.$1) && !t.isAfter(bounds.$2);
  }

  List<Map<String, Object?>> _visibleHistoryTransactions(int tabIndex) {
    return _filteredTransactions(tabIndex)
        .where(_txMatchesHistoryDateFilter)
        .toList();
  }

  Future<void> _applyHistoryDatePreset(_HistoryDatePreset v) async {
    final now = DateTime.now();
    if (v == _HistoryDatePreset.singleDate) {
      final d = await showDatePicker(
        context: context,
        initialDate: _historySingleDate ?? now,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 2, 12, 31),
      );
      if (!mounted) return;
      if (d == null) return;
      setState(() {
        _historyDatePreset = _HistoryDatePreset.singleDate;
        _historySingleDate = d;
      });
      return;
    }
    if (v == _HistoryDatePreset.dateRange) {
      final initial = _historyRangeStart != null && _historyRangeEnd != null
          ? DateTimeRange(start: _historyRangeStart!, end: _historyRangeEnd!)
          : null;
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 2, 12, 31),
        initialDateRange: initial,
      );
      if (!mounted) return;
      if (r == null) return;
      setState(() {
        _historyDatePreset = _HistoryDatePreset.dateRange;
        _historyRangeStart = r.start;
        _historyRangeEnd = r.end;
      });
      return;
    }
    setState(() {
      _historyDatePreset = v;
    });
  }

  String _historyDateFilterHintText() {
    switch (_historyDatePreset) {
      case _HistoryDatePreset.singleDate:
        if (_historySingleDate == null) return '';
        final d = _historySingleDate!;
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      case _HistoryDatePreset.dateRange:
        if (_historyRangeStart == null || _historyRangeEnd == null) {
          return '';
        }
        String fmt(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return '${fmt(_historyRangeStart!)} → ${fmt(_historyRangeEnd!)}';
      default:
        return '';
    }
  }

  String _historyEmptyMessage() {
    final hasPeriod = _historyDateBounds() != null;
    if (hasPeriod) {
      return 'No transactions in this period for the selected tab.';
    }
    return 'No transactions in this category.';
  }

  DateTime? _parseTxDate(Map<String, Object?> row) {
    final raw = row['created_at'] ?? row['createdAt'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  Widget _buildTransactionTile(Map<String, Object?> row) {
    final typeKey = _txTypeKey(row);
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final note = (row['note'] ?? '').toString().trim();
    final when = _parseTxDate(row);
    final dateStr = when == null
        ? '—'
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
            '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final signedPrefix = amount >= 0 ? '+' : '';
    final amountColor = amount >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        isThreeLine: note.isNotEmpty,
        title: Text(
          _txTypeLabel(typeKey),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 13)),
          ],
        ),
        trailing: Text(
          '$signedPrefix$_currencySymbol${formatMoney(amount.abs())}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: amountColor,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    final tabIndex = _historyTabController.index;
    final filtered = _visibleHistoryTransactions(tabIndex);
    final hint = _historyDateFilterHintText();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Transaction history',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Period',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_HistoryDatePreset>(
              value: _historyDatePreset,
              isExpanded: true,
              isDense: true,
              items: const [
                DropdownMenuItem(
                  value: _HistoryDatePreset.allTime,
                  child: Text('All dates'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.today,
                  child: Text('Today'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.thisWeek,
                  child: Text('This week'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.lastWeek,
                  child: Text('Last week'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.thisMonth,
                  child: Text('This month'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.lastMonth,
                  child: Text('Last month'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.thisYear,
                  child: Text('This year'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.lastYear,
                  child: Text('Last year'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.singleDate,
                  child: Text('Specific date…'),
                ),
                DropdownMenuItem(
                  value: _HistoryDatePreset.dateRange,
                  child: Text('Date range…'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                _applyHistoryDatePreset(v);
              },
            ),
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
          ),
        ],
        const SizedBox(height: 8),
        TabBar(
          controller: _historyTabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Deposits'),
            Tab(text: 'Withdraws'),
            Tab(text: 'Transfers'),
            Tab(text: 'Payments'),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _historyEmptyMessage(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (context, i) => _buildTransactionTile(filtered[i]),
          ),
      ],
    );
  }

  Future<void> _showAmountDialog(String action) async {
    if (widget.client.id == null || _saving) return;
    final amountController = TextEditingController();
    final isDeposit = action == 'deposit';
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isDeposit ? 'Deposit funds' : 'Withdraw funds'),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '$_currencySymbol ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(
                    amountController.text.trim().replaceAll(',', '.'),
                  ) ??
                  0;
              if (amount <= 0) return;
              final signed = isDeposit ? amount : -amount;
              if (!isDeposit && amount > _balance) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Insufficient account balance')),
                );
                return;
              }
              setState(() => _saving = true);
              try {
                final isRemote = await _auth.isRemoteUser();
                if (isRemote) {
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
                double autoPaid = 0;
                if (isDeposit) {
                  autoPaid = await _autoSettleDebtFromAccount(
                    isRemote: isRemote,
                  );
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                await _load();
                if (autoPaid > 0 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Applied $_currencySymbol${formatMoney(autoPaid)} from account to outstanding debt.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Failed: $e')),
                );
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<double> _autoSettleDebtFromAccount({required bool isRemote}) async {
    final clientId = widget.client.id;
    if (clientId == null) return 0;
    final customerName = widget.client.name.trim();
    if (customerName.isEmpty) return 0;
    if (isRemote) {
      final balance = (await _auth.fetchRemoteClientAccountBalance(clientId)) ?? 0;
      if (balance <= 0) return 0;
      final remoteDebts = await _auth.getRemoteAuthorized(path: '/debts');
      if (remoteDebts['success'] != true) return 0;
      final rows = remoteDebts['data'];
      double outstanding = 0;
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          final map = Map<String, dynamic>.from(row);
          final name = (map['customer_name'] ?? map['customerName'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final isPaid = ((map['is_paid'] ?? map['isPaid'] ?? 0) as num?)?.toInt() == 1;
          final amount = (map['amount'] as num?)?.toDouble() ?? 0;
          if (!isPaid && name == customerName.toLowerCase()) {
            outstanding += amount;
          }
        }
      }
      final toPay = outstanding < balance ? outstanding : balance;
      if (toPay <= 0) return 0;
      final result = await _auth.payRemoteDebt(
        customerName: customerName,
        amount: toPay,
        clientId: clientId,
        useClientAccount: true,
      );
      if (result['success'] != true) {
        throw StateError((result['message'] ?? 'Debt payment failed').toString());
      }
      return toPay;
    }

    final balance = await _db.getClientAccountBalance(clientId);
    if (balance <= 0) return 0;
    final outstanding = await _db.getOutstandingDebtForCustomer(customerName);
    final toPay = outstanding < balance ? outstanding : balance;
    if (toPay <= 0) return 0;
    await _db.payDebtForCustomerFromClientAccount(
      clientId: clientId,
      customerName: customerName,
      paymentAmount: toPay,
      storeId: widget.client.storeId,
    );
    return toPay;
  }

  Future<void> _goToTransfer() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientAccountTransferScreen(
          sourceClient: widget.client,
          sourceBalance: _balance,
        ),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _goToLoan() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientLoansScreen(client: widget.client),
      ),
    );
    if (ok == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client account')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF60A5FA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Client Account',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _hideAccountCardDetails
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.white,
                            ),
                            tooltip: _hideAccountCardDetails
                                ? 'Show name, account number, and balance'
                                : 'Hide name, account number, and balance',
                            onPressed: () => setState(
                              () => _hideAccountCardDetails =
                                  !_hideAccountCardDetails,
                            ),
                          ),
                          const Icon(Icons.credit_card, color: Colors.white),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _displayAccountName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _displayAccountNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Available balance',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _displayBalanceOnCard,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading || _saving ? null : () => _showAmountDialog('withdraw'),
                    icon: const Icon(Icons.arrow_downward),
                    label: const Text('Withdraw'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading || _saving ? null : () => _showAmountDialog('deposit'),
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('Deposit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading || _saving ? null : _goToTransfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transfer funds'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading || _saving ? null : _goToLoan,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Loan management'),
              ),
            ),
            const SizedBox(height: 20),
            if (widget.client.id != null) _buildHistorySection(Theme.of(context)),
          ],
        ),
      ),
    );
  }
}

enum _HistoryDatePreset {
  allTime,
  today,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisYear,
  lastYear,
  singleDate,
  dateRange,
}
