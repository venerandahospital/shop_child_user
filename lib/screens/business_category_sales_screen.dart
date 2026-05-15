import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

enum BusinessSalesCategory { hardware, supermarket, wholesale, service }

class BusinessCategorySalesScreen extends StatefulWidget {
  const BusinessCategorySalesScreen({
    super.key,
    required this.category,
  });

  final BusinessSalesCategory category;

  @override
  State<BusinessCategorySalesScreen> createState() =>
      _BusinessCategorySalesScreenState();
}

class _BusinessCategorySalesScreenState extends State<BusinessCategorySalesScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  String _currencySymbol = 'USh';
  List<Map<String, Object?>> _rows = [];
  DateTimeRange? _dateRange;
  _BusinessQuickRange? _quickRange;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    final now = DateTime.now();
    _dateRange = DateTimeRange(start: now, end: now);
    _quickRange = _BusinessQuickRange.today;
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

  String get _title {
    switch (widget.category) {
      case BusinessSalesCategory.hardware:
        return 'Hardware transactions';
      case BusinessSalesCategory.supermarket:
        return 'Supermarket transactions';
      case BusinessSalesCategory.wholesale:
        return 'Wholesale transactions';
      case BusinessSalesCategory.service:
        return 'Service transactions';
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rangeStart = _dateRange == null
        ? null
        : DateTime(
            _dateRange!.start.year,
            _dateRange!.start.month,
            _dateRange!.start.day,
          );
    final rangeEnd = _dateRange == null
        ? null
        : DateTime(
            _dateRange!.end.year,
            _dateRange!.end.month,
            _dateRange!.end.day,
            23,
            59,
            59,
            999,
          );
    final data = await _authService.isRemoteUser()
        ? await _authService.fetchRemoteSalesHistory(start: rangeStart, end: rangeEnd)
        : (rangeStart != null && rangeEnd != null
            ? await _db.getSalesWithItemDetailsInRange(start: rangeStart, end: rangeEnd)
            : await _db.getSalesWithItemDetails());
    if (!mounted) return;
    setState(() {
      _rows = data;
      _loading = false;
    });
  }

  bool _isBusinessCategory(String? raw, String value) {
    final text = (raw ?? '').toLowerCase();
    return text.contains('business: $value');
  }

  bool _isSaleCategory(String? raw, String value) {
    final text = (raw ?? '').toLowerCase();
    return text.contains('sale: $value');
  }

  bool _matchesCategory(String? raw) {
    switch (widget.category) {
      case BusinessSalesCategory.hardware:
        return _isBusinessCategory(raw, 'hardware');
      case BusinessSalesCategory.supermarket:
        return _isBusinessCategory(raw, 'supermarket') &&
            _isSaleCategory(raw, 'retail');
      case BusinessSalesCategory.wholesale:
        return _isBusinessCategory(raw, 'supermarket') &&
            _isSaleCategory(raw, 'wholesale');
      case BusinessSalesCategory.service:
        return _isSaleCategory(raw, 'service');
    }
  }

  DateTime? _lineDate(Map<String, Object?> row) {
    return DateTime.tryParse((row['created_at'] as String?) ?? '');
  }

  List<Map<String, Object?>> get _filteredRows {
    final rows = _rows.where((row) {
      if (!_matchesCategory(row['item_category'] as String?)) return false;
      return true;
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

  double get _totalAmount => _filteredRows.fold<double>(
        0,
        (sum, row) => sum + ((row['line_total'] as num?)?.toDouble() ?? 0),
      );

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _dateRange ?? DateTimeRange(start: now, end: now);
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
    _load();
  }

  void _setQuickRangeToday() {
    final now = DateTime.now();
    setState(() {
      _dateRange = DateTimeRange(start: now, end: now);
      _quickRange = _BusinessQuickRange.today;
    });
    _load();
  }

  void _setQuickRangeWeek() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
      _quickRange = _BusinessQuickRange.lastWeek;
    });
    _load();
  }

  void _setQuickRangeMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, now.day);
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
      _quickRange = _BusinessQuickRange.lastMonth;
    });
    _load();
  }

  void _clearDateRange() {
    setState(() {
      _dateRange = null;
      _quickRange = _BusinessQuickRange.all;
    });
    _load();
  }

  static String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '-';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _filteredRows;
    return Scaffold(
      appBar: AppBar(
        title: SectionPageTitle(pageTitle: _title),
        actions: [
          IconButton(
            tooltip: 'Filter by date',
            onPressed: _pickDateRange,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
          if (_dateRange != null)
            IconButton(
              tooltip: 'Clear date filter',
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
                            selected: _quickRange == _BusinessQuickRange.today,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Today'),
                            onSelected: (_) => _setQuickRangeToday(),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _BusinessQuickRange.lastWeek,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Last week'),
                            onSelected: (_) => _setQuickRangeWeek(),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _BusinessQuickRange.lastMonth,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Last month'),
                            onSelected: (_) => _setQuickRangeMonth(),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _BusinessQuickRange.all,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('All'),
                            onSelected: (_) => _clearDateRange(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: ListTile(
                      title: Text('Transactions: ${rows.length}'),
                      subtitle: Text(
                        'Total: $_currencySymbol${formatMoney(_totalAmount)}',
                      ),
                    ),
                  ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 90),
                      child: Center(child: Text('No transactions found.')),
                    )
                  else
                    ...rows.map((row) {
                      final itemName = toTitleCaseWords((row['item_name'] as String?) ?? '');
                      final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
                      final unit = ((row['item_unit'] as String?) ?? '').trim();
                      final unitLabel = unit.isEmpty
                          ? formatDisplayNumber(qty)
                          : '${formatDisplayNumber(qty)} $unit';
                      final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
                      final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;
                      final saleId = row['sale_id'];
                      final createdAt = _fmtDate(row['created_at'] as String?);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: ListTile(
                          title: Text(itemName.isEmpty ? 'Item' : itemName),
                          subtitle: Text(
                            'Sale #$saleId\nQty: $unitLabel  •  Unit: $_currencySymbol${formatMoney(unitPrice)}\n$createdAt',
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

enum _BusinessQuickRange { today, lastWeek, lastMonth, all }
