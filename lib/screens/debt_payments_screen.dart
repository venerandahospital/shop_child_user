import 'package:flutter/material.dart';

import '../models/debt_payment.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';

class DebtPaymentsScreen extends StatefulWidget {
  const DebtPaymentsScreen({super.key});

  @override
  State<DebtPaymentsScreen> createState() => _DebtPaymentsScreenState();
}

class _DebtPaymentsScreenState extends State<DebtPaymentsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;
  bool _loading = true;
  String _currencySymbol = 'USh';
  List<DebtPayment> _payments = [];

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
    final payments = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchDebtPayments()
        : await _db.getDebtPayments();
    if (!mounted) return;
    setState(() {
      _payments = payments;
      _loading = false;
    });
  }

  String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _payments.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No debt payments recorded yet.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: _payments.length,
                    itemBuilder: (context, index) {
                      final p = _payments[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(p.customerName.toUpperCase()),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Paid: $_currencySymbol${formatMoney(p.paidAmount)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Balance after payment: $_currencySymbol${formatMoney(p.remainingBalance)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                _fmtDate(p.createdAt),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                          leading: const Icon(Icons.payments_outlined),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

