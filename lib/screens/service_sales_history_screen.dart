import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

class ServiceSalesHistoryScreen extends StatefulWidget {
  const ServiceSalesHistoryScreen({super.key});

  @override
  State<ServiceSalesHistoryScreen> createState() => _ServiceSalesHistoryScreenState();
}

class _ServiceSalesHistoryScreenState extends State<ServiceSalesHistoryScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  String _currencySymbol = 'USh';
  List<Map<String, Object?>> _rows = [];
  DateTimeRange? _dateRange;
  _ServiceSalesQuickRange? _quickRange;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: now.subtract(const Duration(days: 6)),
      end: now,
    );
    _quickRange = _ServiceSalesQuickRange.lastWeek;
    _load();
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _appSettings.currencySymbol);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _auth.isRemoteUser()
        ? await RemoteSyncService.instance.fetchSalesHistory()
        : await _db.getSalesWithItemDetails();
    if (!mounted) return;
    setState(() {
      _rows = data;
      _loading = false;
    });
  }

  bool _isServiceCategory(String? raw) {
    final text = (raw ?? '').toLowerCase().trim();
    if (text.isEmpty) return false;
    return text.contains('sale: service') || text == 'service';
  }

  DateTime? _lineDate(Map<String, Object?> row) {
    return DateTime.tryParse((row['created_at'] as String?) ?? '');
  }

  List<Map<String, Object?>> get _serviceRows {
    final rows = _rows.where((row) {
      if (!_isServiceCategory(row['item_category'] as String?)) return false;
      if (_dateRange == null) return true;
      final created = _lineDate(row);
      if (created == null) return false;
      final start = DateTime(
        _dateRange!.start.year,
        _dateRange!.start.month,
        _dateRange!.start.day,
      );
      final end = DateTime(
        _dateRange!.end.year,
        _dateRange!.end.month,
        _dateRange!.end.day,
        23,
        59,
        59,
        999,
      );
      return !created.isBefore(start) && !created.isAfter(end);
    }).toList();
    rows.sort((a, b) {
      final bDate = _lineDate(b);
      final aDate = _lineDate(a);
      if (aDate == null && bDate == null) return 0;
      if (bDate == null) return -1;
      if (aDate == null) return 1;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  double get _serviceTotal => _serviceRows.fold<double>(
    0,
    (sum, row) => sum + ((row['line_total'] as num?)?.toDouble() ?? 0),
  );

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _dateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _dateRange = picked;
      _quickRange = null;
    });
  }

  void _setQuickRangeToday() {
    final now = DateTime.now();
    setState(() {
      _dateRange = DateTimeRange(start: now, end: now);
      _quickRange = _ServiceSalesQuickRange.today;
    });
  }

  void _setQuickRangeWeek() {
    final now = DateTime.now();
    setState(() {
      _dateRange = DateTimeRange(
        start: now.subtract(const Duration(days: 6)),
        end: now,
      );
      _quickRange = _ServiceSalesQuickRange.lastWeek;
    });
  }

  void _setQuickRangeMonth() {
    final now = DateTime.now();
    setState(() {
      _dateRange = DateTimeRange(
        start: DateTime(now.year, now.month - 1, now.day),
        end: now,
      );
      _quickRange = _ServiceSalesQuickRange.lastMonth;
    });
  }

  void _clearDateRange() {
    setState(() {
      _dateRange = null;
      _quickRange = _ServiceSalesQuickRange.all;
    });
  }

  static String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _serviceRows;
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Service transactions'),
        actions: [
          IconButton(
            tooltip: 'Clear filter',
            onPressed: _clearDateRange,
            icon: const Icon(Icons.clear),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickDateRange,
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            _dateRange == null
                                ? 'Pick range'
                                : '${_dateRange!.start.year.toString().padLeft(4, '0')}-${_dateRange!.start.month.toString().padLeft(2, '0')}-${_dateRange!.start.day.toString().padLeft(2, '0')} to ${_dateRange!.end.year.toString().padLeft(4, '0')}-${_dateRange!.end.month.toString().padLeft(2, '0')}-${_dateRange!.end.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                        ChoiceChip(
                          selected: _quickRange == _ServiceSalesQuickRange.today,
                          label: const Text('Today'),
                          onSelected: (_) => _setQuickRangeToday(),
                        ),
                        ChoiceChip(
                          selected: _quickRange == _ServiceSalesQuickRange.lastWeek,
                          label: const Text('Last week'),
                          onSelected: (_) => _setQuickRangeWeek(),
                        ),
                        ChoiceChip(
                          selected: _quickRange == _ServiceSalesQuickRange.lastMonth,
                          label: const Text('Last month'),
                          onSelected: (_) => _setQuickRangeMonth(),
                        ),
                        ChoiceChip(
                          selected: _quickRange == _ServiceSalesQuickRange.all,
                          label: const Text('All'),
                          onSelected: (_) => _clearDateRange(),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: ListTile(
                      title: Text('Transactions: ${rows.length}'),
                      subtitle: Text(
                        'Total services: $_currencySymbol${formatMoney(_serviceTotal)}',
                      ),
                    ),
                  ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 90),
                      child: Center(child: Text('No service transactions found.')),
                    )
                  else
                    ...rows.map((row) {
                      final itemName = toTitleCaseWords((row['item_name'] as String?) ?? '');
                      final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
                      final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
                      final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;
                      final saleId = row['sale_id'];
                      final createdAt = _fmtDate(row['created_at'] as String?);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: ListTile(
                          title: Text(itemName.isEmpty ? 'Service item' : itemName),
                          subtitle: Text(
                            'Sale #$saleId\nQty: ${formatDisplayNumber(qty)}  •  Unit: $_currencySymbol${formatMoney(unitPrice)}\n$createdAt',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            '$_currencySymbol${formatMoney(lineTotal)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

enum _ServiceSalesQuickRange { today, lastWeek, lastMonth, all }

