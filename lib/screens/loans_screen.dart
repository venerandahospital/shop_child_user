import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/loan.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import 'loan_form_screen.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;

  bool _loading = true;
  List<Loan> _loans = [];
  Map<int, String> _clientNames = {};
  String _currencySymbol = 'USh';

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
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    List<Loan> loans;
    List<Client> clients;
    if (isRemote) {
      loans = await _auth.fetchRemoteLoans();
      clients = await RemoteSyncService.instance.fetchClients();
    } else {
      loans = await _db.getLoans();
      clients = await _db.getClients();
    }
    final names = <int, String>{};
    for (final c in clients) {
      if (c.id != null) {
        names[c.id!] = c.name;
      }
    }
    if (!mounted) return;
    setState(() {
      _loans = loans;
      _clientNames = names;
      _loading = false;
    });
  }

  String _clientLabel(int clientId) {
    return (_clientNames[clientId] ?? 'Client #$clientId').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  const Center(child: CircularProgressIndicator()),
                ],
              )
            : _loans.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No loans yet. Tap + to record a loan for a client.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _loans.length,
                    itemBuilder: (context, i) {
                      final loan = _loans[i];
                      final due = loan.expectedPaymentDate;
                      final dueStr =
                          '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            _clientLabel(loan.clientId),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          isThreeLine: true,
                          subtitle: Text(
                            'Principal: $_currencySymbol${formatMoney(loan.principalAmount)}\n'
                            'Interest: ${loan.annualInterestPercent.toStringAsFixed(2)}% p.a. · Accrued: $_currencySymbol${formatMoney(loan.interestAmount)}\n'
                            'Total due: $_currencySymbol${formatMoney(loan.totalDue)} · Due: $dueStr',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Loan payment',
                                icon: const Icon(Icons.payments_outlined),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Loan payment action will be added here.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              loan.status == 'paid'
                                  ? Icon(Icons.check_circle, color: Colors.green[700])
                                  : const Icon(Icons.schedule),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading
            ? null
            : () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const LoanFormScreen()),
                );
                if (ok == true) await _load();
              },
        child: const Icon(Icons.add),
      ),
    );
  }
}
