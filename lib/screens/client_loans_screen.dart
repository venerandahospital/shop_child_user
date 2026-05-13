import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/loan.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import 'loan_form_screen.dart';

class ClientLoansScreen extends StatefulWidget {
  const ClientLoansScreen({super.key, required this.client});

  final Client client;

  @override
  State<ClientLoansScreen> createState() => _ClientLoansScreenState();
}

class _ClientLoansScreenState extends State<ClientLoansScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;

  bool _loading = true;
  bool _paying = false;
  String _currencySymbol = 'USh';
  List<Loan> _loans = const [];
  List<Map<String, Object?>> _payments = const [];

  @override
  void initState() {
    super.initState();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrency);
    _load();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrency);
    super.dispose();
  }

  void _onCurrency() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  Future<void> _load() async {
    final clientId = widget.client.id;
    if (clientId == null) return;
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final loans = isRemote
        ? (await _auth.fetchRemoteLoans()).where((l) => l.clientId == clientId).toList()
        : await _db.getLoansForClient(clientId);
    final payments = isRemote
        ? await _auth.fetchRemoteLoanPayments(clientId: clientId)
        : await _db.getLoanPayments(clientId: clientId);
    if (!mounted) return;
    setState(() {
      _loans = loans;
      _payments = payments;
      _loading = false;
    });
  }

  double _paidForLoan(int loanId) {
    double sum = 0;
    for (final p in _payments) {
      final id = (p['loan_id'] as num?)?.toInt();
      if (id == loanId) {
        sum += (p['paid_amount'] as num?)?.toDouble() ?? 0;
      }
    }
    return sum;
  }

  double _remainingForLoan(Loan loan) {
    final rem = loan.totalDue - _paidForLoan(loan.id ?? -1);
    return rem < 0 ? 0 : rem;
  }

  Future<void> _showTerms() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Loan terms & conditions'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Loan amount is disbursed to client account immediately.\n'
            '2. Interest is charged as agreed before disbursement.\n'
            '3. Repayment can be done in installments until balance is cleared.\n'
            '4. Late payment may attract additional penalties based on your policy.\n'
            '5. Final closure happens when remaining balance reaches zero.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _payLoan(Loan loan) async {
    final loanId = loan.id;
    final clientId = widget.client.id;
    if (loanId == null || clientId == null) return;
    final remaining = _remainingForLoan(loan);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This loan is already fully paid.')),
      );
      return;
    }
    final controller = TextEditingController(text: formatDisplayNumber(remaining));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay loan'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '$_currencySymbol ',
            helperText: 'Remaining: $_currencySymbol${formatMoney(remaining)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    if (amount <= 0) return;
    setState(() => _paying = true);
    try {
      if (await _auth.isRemoteUser()) {
        final res = await _auth.postRemoteLoanPayment(
          loanId: loanId,
          clientId: clientId,
          amount: amount,
          storeId: loan.storeId,
        );
        if (res['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((res['message'] ?? 'Payment failed').toString())),
          );
          return;
        }
      } else {
        await _db.payLoan(
          loanId: loanId,
          clientId: clientId,
          amount: amount,
          storeId: loan.storeId,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client loan management'),
        actions: [
          IconButton(
            tooltip: 'Terms & conditions',
            onPressed: _showTerms,
            icon: const Icon(Icons.description_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  widget.client.name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                if (_loans.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No running loans for this client.'),
                    ),
                  )
                else
                  ..._loans.map((loan) {
                    final remaining = _remainingForLoan(loan);
                    return Card(
                      child: ListTile(
                        title: Text(
                          'Loan #${loan.id ?? '-'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Total due: $_currencySymbol${formatMoney(loan.totalDue)}\n'
                          'Paid: $_currencySymbol${formatMoney(_paidForLoan(loan.id ?? -1))}\n'
                          'Remaining: $_currencySymbol${formatMoney(remaining)}',
                        ),
                        trailing: ElevatedButton.icon(
                          onPressed: _paying || remaining <= 0 ? null : () => _payLoan(loan),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pay'),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  'Loan payments',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                if (_payments.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No loan payments yet.'),
                    ),
                  )
                else
                  ..._payments.map((p) {
                    final amount = (p['paid_amount'] as num?)?.toDouble() ?? 0;
                    final rem = (p['remaining_balance'] as num?)?.toDouble() ?? 0;
                    final when = (p['created_at'] ?? '').toString();
                    return Card(
                      child: ListTile(
                        title: Text(
                          'Paid $_currencySymbol${formatMoney(amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Remaining: $_currencySymbol${formatMoney(rem)}\n$when',
                        ),
                      ),
                    );
                  }),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading
            ? null
            : () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => LoanFormScreen(
                      initialClientId: widget.client.id,
                      lockClient: true,
                    ),
                  ),
                );
                if (ok == true) {
                  await _load();
                }
              },
        icon: const Icon(Icons.add),
        label: const Text('Take loan'),
      ),
    );
  }
}

