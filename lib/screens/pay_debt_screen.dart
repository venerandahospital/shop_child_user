import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';

enum _PayMethod { cash, clientAccount, mtn, airtel }

class PayDebtScreen extends StatefulWidget {
  const PayDebtScreen({
    super.key,
    required this.customerName,
    required this.amountOwed,
    this.client,
  });

  final String customerName;
  final double amountOwed;
  final Client? client;

  @override
  State<PayDebtScreen> createState() => _PayDebtScreenState();
}

class _PayDebtScreenState extends State<PayDebtScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  final _amountController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _currencySymbol = 'USh';
  Client? _client;
  double _accountBalance = 0;
  _PayMethod _payMethod = _PayMethod.cash;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    Client? resolved = widget.client;
    resolved ??= await _db.getClientByNormalizedName(widget.customerName);
    var balance = 0.0;
    if (resolved?.id != null) {
      final isRemote = await _auth.isRemoteUser();
      if (isRemote) {
        balance = await _auth.fetchRemoteClientAccountBalance(resolved!.id!) ?? 0;
      } else {
        balance = await _db.getClientAccountBalance(resolved!.id!);
      }
    }
    if (!mounted) return;
    setState(() {
      _client = resolved;
      _accountBalance = balance;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final payAmount = double.tryParse(
          _amountController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    if (payAmount <= 0 || payAmount > widget.amountOwed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid payment amount')),
      );
      return;
    }
    if (_payMethod == _PayMethod.clientAccount && payAmount > _accountBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient client account balance')),
      );
      return;
    }
    if (_payMethod == _PayMethod.mtn || _payMethod == _PayMethod.airtel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mobile money integration coming soon.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final useClientAccount = _payMethod == _PayMethod.clientAccount;
      final isRemote = await _auth.isRemoteUser();
      double remaining;
      if (isRemote) {
        final remote = await _auth.payRemoteDebt(
          customerName: widget.customerName,
          amount: payAmount,
          clientId: _client?.id,
          useClientAccount: useClientAccount,
        );
        if (remote['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((remote['message'] ?? 'Payment failed').toString())),
          );
          return;
        }
        remaining = (remote['remaining'] as num?)?.toDouble() ?? 0;
      } else {
        remaining = useClientAccount
            ? await _db.payDebtForCustomerFromClientAccount(
                clientId: _client!.id!,
                customerName: widget.customerName,
                paymentAmount: payAmount,
                storeId: _client!.storeId,
              )
            : await _db.payDebtForCustomer(
                customerName: widget.customerName,
                paymentAmount: payAmount,
              );
      }
      if (!mounted) return;
      final msg = remaining <= 0
          ? '${widget.customerName} has fully paid.'
          : 'New balance: $_currencySymbol${formatMoney(remaining)}';
      Navigator.of(context).pop(msg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay debt')),
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
                        Text('Client: ${widget.customerName.toUpperCase()}'),
                        const SizedBox(height: 6),
                        Text(
                          'Amount owed: $_currencySymbol${formatMoney(widget.amountOwed)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (_client?.id != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Account balance: $_currencySymbol${formatMoney(_accountBalance)}',
                          ),
                        ],
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
                        Text(
                          'Payment method',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        DropdownButtonFormField<_PayMethod>(
                          initialValue: _payMethod,
                          decoration: const InputDecoration(
                            labelText: 'Method',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: _PayMethod.cash,
                              child: Text('Cash'),
                            ),
                            DropdownMenuItem(
                              value: _PayMethod.clientAccount,
                              child: Text('Client account'),
                            ),
                            DropdownMenuItem(
                              value: _PayMethod.mtn,
                              child: Text('MTN Mobile Money (coming soon)'),
                            ),
                            DropdownMenuItem(
                              value: _PayMethod.airtel,
                              child: Text('Airtel Money (coming soon)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            if (v == _PayMethod.clientAccount &&
                                (_client?.id == null || _accountBalance <= 0)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Client account is unavailable for this payment.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setState(() => _payMethod = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Amount to pay',
                            prefixText: '$_currencySymbol ',
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
        child: ElevatedButton(
          onPressed: _loading || _saving ? null : _submit,
          child: Text(_saving ? 'Saving...' : 'Save payment'),
        ),
      ),
    );
  }
}
