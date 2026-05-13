import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/loan.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';

class LoanFormScreen extends StatefulWidget {
  const LoanFormScreen({
    super.key,
    this.initialClientId,
    this.lockClient = false,
  });

  final int? initialClientId;
  final bool lockClient;

  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

enum _InterestRatePeriod { yearly, monthly }

class _LoanFormScreenState extends State<LoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  final _principalController = TextEditingController();
  final _interestController = TextEditingController();
  final _noteController = TextEditingController();

  List<Client> _clients = [];
  int? _clientId;
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 30));
  bool _loadingClients = true;
  bool _saving = false;
  String _currencySymbol = 'USh';
  _InterestRatePeriod _interestPeriod = _InterestRatePeriod.yearly;

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? helper,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixText: prefixText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _interestController.text = '0';
    _currencySymbol = _settings.currencySymbol;
    _loadClients();
  }

  @override
  void dispose() {
    _principalController.dispose();
    _interestController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _loadingClients = true);
    final isRemote = await _auth.isRemoteUser();
    final list = isRemote
        ? await RemoteSyncService.instance.fetchClients()
        : await _db.getClients();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _clients = list.where((c) => c.id != null).toList();
      if (widget.initialClientId != null &&
          _clients.any((c) => c.id == widget.initialClientId)) {
        _clientId = widget.initialClientId;
      } else {
        _clientId = _clients.isNotEmpty ? _clients.first.id : null;
      }
      _loadingClients = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _expectedDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final clientId = _clientId;
    if (clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a client')),
      );
      return;
    }
    final principal = double.tryParse(
          _principalController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    if (principal <= 0) return;
    final interestPctInput = double.tryParse(
          _interestController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    final annualInterestPercent = _interestPeriod == _InterestRatePeriod.monthly
        ? (interestPctInput * 12)
        : interestPctInput;
    final now = DateTime.now();
    final accrued = Loan.computeAccrued(
      principal: principal,
      annualInterestPercent: annualInterestPercent,
      issuedAt: now,
      expectedPaymentDate: _expectedDate,
    );
    final client = _clients.firstWhere((c) => c.id == clientId);
    final loan = Loan(
      storeId: client.storeId,
      clientId: clientId,
      principalAmount: principal,
      annualInterestPercent: annualInterestPercent,
      expectedPaymentDate: _expectedDate,
      interestAmount: accrued.interest,
      totalDue: accrued.total,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    setState(() => _saving = true);
    try {
      if (await _auth.isRemoteUser()) {
        final res = await _auth.postRemoteAuthorized(
          path: '/loans',
          body: loan.toRemoteBody(),
        );
        if (res['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (res['message'] ?? 'Could not save loan').toString(),
              ),
            ),
          );
          return;
        }
        final disburse = await _auth.postRemoteClientAccountTransaction(
          clientId: clientId,
          amount: principal,
          transactionType: 'loan_disbursement',
          note: 'Loan disbursement',
        );
        if (disburse['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (disburse['message'] ?? 'Could not record loan disbursement')
                    .toString(),
              ),
            ),
          );
          return;
        }
      } else {
        await _db.upsertLoan(loan);
        await _db.recordClientAccountTransaction(
          clientId: clientId,
          storeId: client.storeId,
          transactionType: 'loan_disbursement',
          amount: principal,
          note: 'Loan disbursement',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = Loan.computeAccrued(
      principal: double.tryParse(
            _principalController.text.trim().replaceAll(',', '.'),
          ) ??
          0,
      annualInterestPercent: (() {
        final parsed = double.tryParse(
            _interestController.text.trim().replaceAll(',', '.'),
          ) ??
            0;
        return _interestPeriod == _InterestRatePeriod.monthly
            ? parsed * 12
            : parsed;
      })(),
      issuedAt: DateTime.now(),
      expectedPaymentDate: _expectedDate,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('New loan')),
      body: _loadingClients
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  InputDecorator(
                    decoration: _fieldDecoration(label: 'Client'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _clientId,
                        isExpanded: true,
                        hint: const Text('Select client'),
                        items: _clients
                            .map(
                              (c) => DropdownMenuItem<int>(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: widget.lockClient
                            ? null
                            : (v) => setState(() => _clientId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _principalController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'Principal amount',
                      prefixText: '$_currencySymbol ',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
                      if (n <= 0) return 'Enter a positive amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _interestController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: _interestPeriod == _InterestRatePeriod.monthly
                          ? 'Interest (% per month)'
                          : 'Interest (% per year)',
                      helper: _interestPeriod == _InterestRatePeriod.monthly
                          ? 'Monthly rate; converted to annual for calculation'
                          : 'Annual rate; simple interest to due date',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_InterestRatePeriod>(
                    segments: const [
                      ButtonSegment<_InterestRatePeriod>(
                        value: _InterestRatePeriod.yearly,
                        label: Text('Per year'),
                      ),
                      ButtonSegment<_InterestRatePeriod>(
                        value: _InterestRatePeriod.monthly,
                        label: Text('Per month'),
                      ),
                    ],
                    selected: {_interestPeriod},
                    onSelectionChanged: (selection) {
                      setState(() => _interestPeriod = selection.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Expected payment date'),
                    subtitle: Text(
                      '${_expectedDate.year}-${_expectedDate.month.toString().padLeft(2, '0')}-${_expectedDate.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: _pickDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estimated at due date',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Accrued interest: $_currencySymbol${formatMoney(preview.interest)}',
                          ),
                          Text(
                            'Total to repay: $_currencySymbol${formatMoney(preview.total)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: _fieldDecoration(label: 'Note (optional)'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save loan'),
                  ),
                ],
              ),
            ),
    );
  }
}
