import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense});

  final Expense? expense;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _currencySymbol = 'USh';
  List<ExpenseCategory> _categories = [];
  String? _selectedCategoryLabel;
  List<String> _paidByOptions = [];
  List<String> _receivedByOptions = [];
  String? _selectedPaidBy;
  String? _selectedReceivedBy;

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
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _appSettings.currencySymbol);
  }

  Future<void> _load() async {
    final categories = await _db.getExpenseCategories();
    final paidByOptions = await _appSettings.getExpensePaidByOptions();
    final receivedByOptions = await _appSettings.getExpenseReceivedByOptions();
    final expense = widget.expense;
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _titleController.text = expense?.title ?? '';
      _amountController.text = expense == null ? '' : formatMoney(expense.amount);
      _notesController.text = expense?.notes ?? '';
      _paidByOptions = paidByOptions;
      _receivedByOptions = receivedByOptions;
      _selectedPaidBy = (expense?.paidBy ?? '').trim().isEmpty ? null : expense!.paidBy;
      _selectedReceivedBy =
          (expense?.receivedBy ?? '').trim().isEmpty ? null : expense!.receivedBy;
      if (_selectedPaidBy != null && !_paidByOptions.contains(_selectedPaidBy)) {
        _paidByOptions = [..._paidByOptions, _selectedPaidBy!];
      }
      if (_selectedReceivedBy != null &&
          !_receivedByOptions.contains(_selectedReceivedBy)) {
        _receivedByOptions = [..._receivedByOptions, _selectedReceivedBy!];
      }
      _selectedCategoryLabel = expense?.category?.trim().isEmpty ?? true ? null : expense!.category;
      if (_selectedCategoryLabel != null &&
          !_categories.any((c) => c.displayLabel == _selectedCategoryLabel)) {
        _selectedCategoryLabel = null;
      }
      _loading = false;
    });
  }

  Future<void> _addExpenseCategoryInline() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add expense category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Category name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final categoryName = (name ?? '').trim();
    if (categoryName.isEmpty) return;
    await _db.insertExpenseCategory(ExpenseCategory(name: categoryName));
    final categories = await _db.getExpenseCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      final match = categories
          .where((c) => c.name.trim().toLowerCase() == categoryName.toLowerCase())
          .firstOrNull;
      _selectedCategoryLabel = match?.displayLabel ?? categoryName;
    });
  }

  Future<void> _addPaidByInline() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add paid-by name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final value = (name ?? '').trim();
    if (value.isEmpty) return;
    if (!_paidByOptions.any((e) => e.toLowerCase() == value.toLowerCase())) {
      _paidByOptions = [..._paidByOptions, value];
      await _appSettings.setExpensePaidByOptions(_paidByOptions);
    }
    if (!mounted) return;
    setState(() => _selectedPaidBy = value);
  }

  Future<void> _addReceivedByInline() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add received-by name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final value = (name ?? '').trim();
    if (value.isEmpty) return;
    if (!_receivedByOptions.any((e) => e.toLowerCase() == value.toLowerCase())) {
      _receivedByOptions = [..._receivedByOptions, value];
      await _appSettings.setExpenseReceivedByOptions(_receivedByOptions);
    }
    if (!mounted) return;
    setState(() => _selectedReceivedBy = value);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;
    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid title and amount')),
      );
      return;
    }
    if ((_selectedPaidBy ?? '').trim().isEmpty ||
        (_selectedReceivedBy ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paid by and received by are required')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.expense;
      final expense = Expense(
        id: existing?.id,
        storeId: existing?.storeId,
        title: title,
        category: _selectedCategoryLabel?.trim().isEmpty ?? true ? null : _selectedCategoryLabel,
        paidBy: _selectedPaidBy,
        receivedBy: _selectedReceivedBy,
        amount: amount,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        createdAt: existing?.createdAt,
      );
      if (await _auth.isRemoteUser()) {
        final remote = await _auth.saveRemoteExpense(expense.toMap());
        if (remote['success'] != true) {
          throw Exception((remote['message'] ?? 'Failed to sync expense').toString());
        }
      } else {
        await _db.upsertExpense(expense);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save expense: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.expense != null;

    return Scaffold(
      appBar: AppBar(
        title: SectionPageTitle(pageTitle: isEdit ? 'Edit expense' : 'New expense'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Expense title',
                    hintText: 'e.g. Transport, Fuel, Stationery',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryLabel,
                  decoration: const InputDecoration(
                    labelText: 'Expense category (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('None'),
                    ),
                    ..._categories.map(
                      (c) => DropdownMenuItem<String>(
                        value: c.displayLabel,
                        child: Text(c.displayLabel),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _selectedCategoryLabel = value),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _addExpenseCategoryInline,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add new category'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaidBy,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: _paidByOptions
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedPaidBy = value),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _addPaidByInline,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add new paid-by'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReceivedBy,
                  decoration: const InputDecoration(labelText: 'Received by'),
                  items: _receivedByOptions
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedReceivedBy = value),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _addReceivedByInline,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add new received-by'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '$_currencySymbol ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
