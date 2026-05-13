import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';
import 'expense_form_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;
  bool _loading = true;
  String _currencySymbol = 'USh';
  List<Expense> _expenses = [];
  _ExpensesQuickRange _quickRange = _ExpensesQuickRange.today;

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
    final expenses = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchExpenses()
        : await _db.getExpenses();
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _loading = false;
    });
  }

  List<Expense> get _filteredExpenses {
    if (_quickRange == _ExpensesQuickRange.all) return _expenses;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    DateTime start;
    switch (_quickRange) {
      case _ExpensesQuickRange.today:
        start = startOfToday;
        break;
      case _ExpensesQuickRange.lastWeek:
        start = startOfToday.subtract(const Duration(days: 6));
        break;
      case _ExpensesQuickRange.lastMonth:
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case _ExpensesQuickRange.all:
        start = DateTime(2000);
        break;
    }
    final end = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );
    return _expenses
        .where((e) => !e.createdAt.isBefore(start) && !e.createdAt.isAfter(end))
        .toList();
  }

  double get _totalExpenses =>
      _filteredExpenses.fold<double>(0, (sum, e) => sum + e.amount);

  Future<void> _openExpenseForm({Expense? expense}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(expense: expense),
      ),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Remove "${expense.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (expense.id == null) return;
    if (await _auth.isRemoteUser()) {
      final remote = await _auth.deleteRemoteExpense(expense.id!);
      if (remote['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (remote['message'] ?? 'Failed to delete expense on mother').toString(),
            ),
          ),
        );
        return;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted')),
      );
      return;
    }
    await _db.deleteExpense(expense.id!);
    await _load();
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Expenses'),
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
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _ExpensesQuickRange.today,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Today'),
                            onSelected: (_) => setState(
                              () => _quickRange = _ExpensesQuickRange.today,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _ExpensesQuickRange.lastWeek,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Last week'),
                            onSelected: (_) => setState(
                              () => _quickRange = _ExpensesQuickRange.lastWeek,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _ExpensesQuickRange.lastMonth,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Last month'),
                            onSelected: (_) => setState(
                              () => _quickRange = _ExpensesQuickRange.lastMonth,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _ExpensesQuickRange.all,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('All'),
                            onSelected: (_) => setState(
                              () => _quickRange = _ExpensesQuickRange.all,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total expenses',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_currencySymbol${formatMoney(_totalExpenses)}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_filteredExpenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text('No expenses yet. Add your first expense.'),
                      ),
                    )
                  else
                    ..._filteredExpenses.map((expense) {
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(expense.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((expense.category ?? '').trim().isNotEmpty)
                                Text(
                                  expense.category!,
                                  style: theme.textTheme.bodySmall,
                                ),
                              if ((expense.paidBy ?? '').trim().isNotEmpty)
                                Text(
                                  'Paid by: ${expense.paidBy}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              if ((expense.receivedBy ?? '').trim().isNotEmpty)
                                Text(
                                  'Received by: ${expense.receivedBy}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              if ((expense.notes ?? '').trim().isNotEmpty)
                                Text(
                                  expense.notes!,
                                  style: theme.textTheme.bodySmall,
                                ),
                              Text(
                                _formatDate(expense.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: SizedBox(
                            width: 132,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    '$_currencySymbol${formatMoney(expense.amount)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openExpenseForm(expense: expense);
                                    } else if (value == 'delete') {
                                      _deleteExpense(expense);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 10),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExpenseForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
    );
  }
}

enum _ExpensesQuickRange { today, lastWeek, lastMonth, all }

