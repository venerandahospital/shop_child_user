import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/client.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/adaptive_card_text.dart';
import '../widgets/section_page_title.dart';
import 'client_details_screen.dart';
import 'service_sales_history_screen.dart';
import 'sales_screen.dart';

double _receiptLineSubtotal(Map<String, Object?> row) {
  final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
  final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
  return (row['line_total'] as num?)?.toDouble() ?? quantity * unitPrice;
}

double _receiptLineDiscountApplied(Map<String, Object?> row) {
  final sub = _receiptLineSubtotal(row);
  final productDiscount = (row['product_discount'] as num?)?.toDouble() ?? 0;
  return productDiscount > sub ? sub : productDiscount;
}

double _receiptLineNetTotal(Map<String, Object?> row) {
  final sub = _receiptLineSubtotal(row);
  final disc = _receiptLineDiscountApplied(row);
  final net = sub - disc;
  return net < 0 ? 0 : net;
}

double _receiptLineUnitSell(Map<String, Object?> row) {
  return (row['unit_price'] as num?)?.toDouble() ?? 0;
}

String _saleCategoryDisplay(String? itemCategory) {
  final raw = (itemCategory ?? '').trim();
  if (raw.isEmpty) return '';
  for (final part in raw.split('|').map((p) => p.trim())) {
    final lower = part.toLowerCase();
    if (lower.startsWith('sale:')) {
      final v = part.substring(part.indexOf(':') + 1).trim();
      return v.isEmpty ? '' : toTitleCaseWords(v);
    }
  }
  return toTitleCaseWords(raw);
}

/// Spaces and hyphens won’t become line-break points (name/category stay one unit).
String _receiptUnbreakableSegment(String s) {
  return s
      .replaceAll(' ', '\u00A0')
      .replaceAll('-', '\u2011');
}

pw.Widget _pdfTableHeaderCell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2, right: 2),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
    ),
  );
}

/// Spans the full content width (unlike a short dash string).
pw.Widget _pdfFullWidthSeparator() {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Divider(
      thickness: 0.7,
      color: PdfColors.grey800,
    ),
  );
}

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  List<Map<String, Object?>> _rows = [];
  List<Map<String, dynamic>> _filteredReceipts = [];
  double _grandTotalValue = 0;
  double _totalBalanceValue = 0;
  double _totalPaidValue = 0;
  int _transactionCountValue = 0;
  double _totalOfHardwareValue = 0;
  double _totalOfWholesaleValue = 0;
  double _totalOfSupermarketValue = 0;
  double _totalOfServicesValue = 0;
  String _currencySymbol = 'USh';
  DateTimeRange? _dateRange;
  _SalesHistoryQuickRange? _quickRange;
  static const int _receiptBatchSize = 12;
  int _visibleReceiptCount = _receiptBatchSize;
  Timer? _progressiveRevealTimer;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    final now = DateTime.now();
    _dateRange = DateTimeRange(start: now, end: now);
    _quickRange = _SalesHistoryQuickRange.today;
    _load();
  }

  @override
  void dispose() {
    _progressiveRevealTimer?.cancel();
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
    setState(() {
      _loading = true;
    });
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
    final isRemote = await _auth.isRemoteUser();
    final data = isRemote
        ? await RemoteSyncService.instance.fetchSalesHistory(
            start: rangeStart,
            end: rangeEnd,
          )
        : (rangeStart != null && rangeEnd != null
              ? await _db.getSalesWithItemDetailsInRange(
                  start: rangeStart,
                  end: rangeEnd,
                )
              : await _db.getSalesWithItemDetails());
    final receipts = _buildReceiptsBySale(data);
    final filtered = _filterReceiptsByDateRange(receipts);
    _recomputeSummaries(filtered);
    if (!mounted) return;
    _progressiveRevealTimer?.cancel();
    final initialVisible = filtered.length < _receiptBatchSize
        ? filtered.length
        : _receiptBatchSize;
    if (filtered.length > initialVisible) {
      _progressiveRevealTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_visibleReceiptCount >= filtered.length) {
            timer.cancel();
            return;
          }
          setState(() {
            _visibleReceiptCount = (_visibleReceiptCount + _receiptBatchSize)
                .clamp(0, filtered.length);
          });
        },
      );
    }
    setState(() {
      _rows = data;
      _filteredReceipts = filtered;
      _visibleReceiptCount = initialVisible;
      _loading = false;
    });
  }

  double get _grandTotal => _grandTotalValue;

  double get _totalBalance => _totalBalanceValue;

  double get _totalPaid => _totalPaidValue;

  int get _transactionCount => _transactionCountValue;

  bool _isBusinessCategory(String? raw, String value) {
    final text = (raw ?? '').toLowerCase();
    return text.contains('business: $value');
  }

  bool _isSaleCategory(String? raw, String value) {
    final text = (raw ?? '').toLowerCase();
    return text.contains('sale: $value');
  }

  double get _totalOfHardware => _totalOfHardwareValue;

  double get _totalOfWholesale => _totalOfWholesaleValue;

  double get _totalOfSupermarket => _totalOfSupermarketValue;

  double get _totalOfServices => _totalOfServicesValue;

  List<Map<String, dynamic>> _buildReceiptsBySale(List<Map<String, Object?>> rows) {
    final bySale = <int, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final saleId = row['sale_id'] as int?;
      if (saleId == null) continue;
      bySale.putIfAbsent(saleId, () => []).add(row);
    }
    final receipts = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final row in rows) {
      final saleId = row['sale_id'] as int?;
      if (saleId == null || seen.contains(saleId)) continue;
      seen.add(saleId);
      final lines = bySale[saleId] ?? [];
      final first = lines.isNotEmpty ? lines.first : row;
      final totalAmount = (first['total_amount'] as num?)?.toDouble() ?? 0;
      final overallDiscount =
          (first['overall_discount'] as num?)?.toDouble() ?? 0;
      final amountReceived = (first['amount_received'] as num?)?.toDouble();
      final balance = (first['balance'] as num?)?.toDouble();
      receipts.add({
        'sale_id': saleId,
        'created_at': first['created_at'],
        'total_amount': totalAmount,
        'overall_discount': overallDiscount,
        'amount_received': amountReceived ?? totalAmount,
        'balance': balance ?? 0,
        'customer_name': first['customer_name'],
        'customer_phone': first['customer_phone'],
        'customer_address': first['customer_address'],
        'payment_method': first['payment_method'],
        'lines': lines,
      });
    }
    return receipts;
  }

  List<Map<String, dynamic>> _filterReceiptsByDateRange(
    List<Map<String, dynamic>> receipts,
  ) {
    if (_dateRange == null) return receipts;
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
    return receipts.where((r) {
      final createdRaw = r['created_at'] as String?;
      final created = DateTime.tryParse(createdRaw ?? '');
      if (created == null) return false;
      return !created.isBefore(start) && !created.isAfter(end);
    }).toList();
  }

  void _recomputeSummaries(List<Map<String, dynamic>> receipts) {
    var grandTotal = 0.0;
    var totalBalance = 0.0;
    var totalHardware = 0.0;
    var totalWholesale = 0.0;
    var totalSupermarket = 0.0;
    var totalServices = 0.0;

    for (final receipt in receipts) {
      grandTotal += (receipt['total_amount'] as num?)?.toDouble() ?? 0;
      totalBalance += (receipt['balance'] as num?)?.toDouble() ?? 0;
      final lines = receipt['lines'] as List<Map<String, Object?>>? ?? const [];
      for (final row in lines) {
        final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;
        final category = row['item_category'] as String?;
        if (_isBusinessCategory(category, 'hardware')) {
          totalHardware += lineTotal;
        }
        final isSupermarket = _isBusinessCategory(category, 'supermarket');
        if (isSupermarket && _isSaleCategory(category, 'wholesale')) {
          totalWholesale += lineTotal;
        }
        if (isSupermarket && _isSaleCategory(category, 'retail')) {
          totalSupermarket += lineTotal;
        }
        if (_isSaleCategory(category, 'service')) {
          totalServices += lineTotal;
        }
      }
    }

    _grandTotalValue = grandTotal;
    _totalBalanceValue = totalBalance;
    final paid = grandTotal - totalBalance;
    _totalPaidValue = paid < 0 ? 0 : paid;
    _transactionCountValue = receipts.length;
    _totalOfHardwareValue = totalHardware;
    _totalOfWholesaleValue = totalWholesale;
    _totalOfSupermarketValue = totalSupermarket;
    _totalOfServicesValue = totalServices;
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

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
    _load();
  }

  void _setQuickRangeToday() {
    final now = DateTime.now();
    setState(() {
      _dateRange = DateTimeRange(start: now, end: now);
      _quickRange = _SalesHistoryQuickRange.today;
    });
    _load();
  }

  void _setQuickRangeWeek() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
      _quickRange = _SalesHistoryQuickRange.lastWeek;
    });
    _load();
  }

  void _setQuickRangeMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, now.day);
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
      _quickRange = _SalesHistoryQuickRange.lastMonth;
    });
    _load();
  }

  void _clearDateRange() {
    setState(() {
      _dateRange = null;
      _quickRange = _SalesHistoryQuickRange.all;
    });
    _load();
  }

  Widget _receiptRow(
    ThemeData theme,
    String label,
    double amount, {
    bool isBalance = false,
    bool isReceived = false,
    bool isEmphasis = false,
  }) {
    final rowColor = isBalance
        ? Colors.red
        : isReceived
            ? Colors.green
            : null;
    final weight = isEmphasis
        ? FontWeight.bold
        : (isBalance || isReceived)
            ? FontWeight.bold
            : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: weight,
              color: rowColor,
            ),
          ),
          Text(
            formatMoney(amount),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: isEmphasis ? FontWeight.bold : FontWeight.w600,
              color: rowColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptTableHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 6, top: 2),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _receiptTableCell(
    Widget child, {
    bool alignEnd = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 6, right: 4),
      child: alignEnd
          ? Align(alignment: Alignment.centerRight, child: child)
          : child,
    );
  }

  Future<Uint8List> _buildReceiptPdfBytes(Map<String, dynamic> receipt) async {
    final pdf = pw.Document();
    final saleId = receipt['sale_id'] as int?;
    final totalAmount = (receipt['total_amount'] as num?)?.toDouble() ?? 0;
    final overallDiscount =
        (receipt['overall_discount'] as num?)?.toDouble() ?? 0;
    final amountReceived =
        (receipt['amount_received'] as num?)?.toDouble() ?? totalAmount;
    final balance = (receipt['balance'] as num?)?.toDouble() ?? 0;
    final customerName = receipt['customer_name'] as String?;
    final customerPhone = receipt['customer_phone'] as String?;
    final customerAddress = receipt['customer_address'] as String?;
    final createdRaw = receipt['created_at'] as String?;
    final lines = receipt['lines'] as List<Map<String, Object?>>? ?? [];
    final grandSubtotal =
        lines.fold<double>(0, (sum, row) => sum + _receiptLineNetTotal(row));
    final pageWidth = 80 * PdfPageFormat.mm;
    final estimatedHeightMm = (145 + (lines.length * 12)).clamp(180, 440).toDouble();
    final pageHeight = estimatedHeightMm * PdfPageFormat.mm;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: const pw.EdgeInsets.fromLTRB(10, 10, 10, 10),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                _appSettings.shopName.toUpperCase(),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'SALES RECEIPT',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'All amounts in $_currencySymbol',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Date: ${_formatDate(createdRaw)}', style: const pw.TextStyle(fontSize: 8)),
            if (saleId != null)
              pw.Text('Receipt #: $saleId', style: const pw.TextStyle(fontSize: 8)),
            if (customerName != null && customerName.trim().isNotEmpty)
              pw.Text(
                'Customer: ${toTitleCaseWords(customerName.trim())}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            if (customerPhone != null && customerPhone.trim().isNotEmpty)
              pw.Text('Phone: ${customerPhone.trim()}', style: const pw.TextStyle(fontSize: 8)),
            if (customerAddress != null && customerAddress.trim().isNotEmpty)
              pw.Text(
                'Address: ${customerAddress.trim()}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            pw.SizedBox(height: 4),
            pw.SizedBox(
              width: double.infinity,
              child: pw.Table(
                tableWidth: pw.TableWidth.max,
                border: pw.TableBorder(
                  top: const pw.BorderSide(color: PdfColors.grey800, width: 0.8),
                  bottom:
                      const pw.BorderSide(color: PdfColors.grey800, width: 0.8),
                  horizontalInside:
                      const pw.BorderSide(color: PdfColors.grey800, width: 0.8),
                  left: pw.BorderSide.none,
                  right: pw.BorderSide.none,
                  verticalInside: pw.BorderSide.none,
                ),
                columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(0.95),
                2: const pw.FlexColumnWidth(0.95),
                3: const pw.FlexColumnWidth(0.95),
                4: const pw.FlexColumnWidth(0.95),
                5: const pw.FlexColumnWidth(0.95),
              },
              children: [
                pw.TableRow(
                  children: [
                    _pdfTableHeaderCell('Item'),
                    _pdfTableHeaderCell('Qty'),
                    _pdfTableHeaderCell('Sell'),
                    _pdfTableHeaderCell('Sub'),
                    _pdfTableHeaderCell('Disc'),
                    _pdfTableHeaderCell('Total'),
                  ],
                ),
                ...lines.map((row) {
                  final name = toTitleCaseWords((row['item_name'] as String?) ?? 'Item');
                  final saleCat = _saleCategoryDisplay(row['item_category'] as String?);
                  final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
                  final unit = ((row['item_unit'] as String?) ?? '').trim();
                  final qtyUnit = unit.isEmpty
                      ? formatDisplayNumber(quantity)
                      : '${formatDisplayNumber(quantity)} $unit';
                  final unitSell = _receiptLineUnitSell(row);
                  final sub = _receiptLineSubtotal(row);
                  final disc = _receiptLineDiscountApplied(row);
                  final net = _receiptLineNetTotal(row);
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3, right: 2),
                        child: pw.Text(
                          saleCat.isEmpty
                              ? _receiptUnbreakableSegment(name)
                              : '${_receiptUnbreakableSegment(name)}\u00A0–\u00A0${_receiptUnbreakableSegment(saleCat)}',
                          style: const pw.TextStyle(fontSize: 7),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3, right: 2),
                        child: pw.Text(qtyUnit, style: const pw.TextStyle(fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3, right: 2),
                        child: pw.Text(
                          formatMoney(unitSell),
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3, right: 2),
                        child: pw.Text(
                          formatMoney(sub),
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3, right: 2),
                        child: pw.Text(
                          formatMoney(disc),
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(
                          formatMoney(net),
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Grand subtotal', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  formatMoney(grandSubtotal),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Overall discount', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  formatMoney(overallDiscount),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            _pdfFullWidthSeparator(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Final grand total',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  formatMoney(totalAmount),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            _pdfFullWidthSeparator(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Amount paid', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  formatMoney(amountReceived),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Balance', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  formatMoney(balance),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'Thank you!',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Future<void> _exportReceipt(Map<String, dynamic> receipt) async {
    final saleId = receipt['sale_id'] as int? ?? 0;
    final bytes = await _buildReceiptPdfBytes(receipt);
    await Printing.sharePdf(bytes: bytes, filename: 'receipt_$saleId.pdf');
  }

  Future<void> _printReceipt(Map<String, dynamic> receipt) async {
    // For now, "Print" also exports/shares PDF as requested.
    await _exportReceipt(receipt);
  }

  Future<void> _openClientFromReceipt(Map<String, dynamic> receipt) async {
    final rawName = (receipt['customer_name'] as String?)?.trim() ?? '';
    if (rawName.isEmpty) return;
    final clients = await _db.getClients();
    if (!mounted) return;
    Client? exact;
    for (final c in clients) {
      if (c.name.trim().toLowerCase() == rawName.toLowerCase()) {
        exact = c;
        break;
      }
    }
    final fallback = Client(
      name: rawName,
      phone: (receipt['customer_phone'] as String?)?.trim().isEmpty ?? true
          ? null
          : (receipt['customer_phone'] as String?)?.trim(),
      address: (receipt['customer_address'] as String?)?.trim().isEmpty ?? true
          ? null
          : (receipt['customer_address'] as String?)?.trim(),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientDetailsScreen(client: exact ?? fallback),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleReceipts = _filteredReceipts.take(_visibleReceiptCount).toList();
    final hasMoreReceipts = _visibleReceiptCount < _filteredReceipts.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SalesScreen()),
        );
      },
      child: Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Sales history'),
        actions: [
          IconButton(
            icon: const Icon(Icons.miscellaneous_services_outlined),
            tooltip: 'Service transactions',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ServiceSalesHistoryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Filter by date',
            onPressed: _pickDateRange,
          ),
          if (_dateRange != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear date filter',
              onPressed: _clearDateRange,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView.builder(
                itemCount: 5,
                itemBuilder: (context, index) => Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(height: 72),
                  ),
                ),
              )
            : _filteredReceipts.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _rows.isEmpty
                              ? 'No sales recorded yet.'
                              : 'No sales found in selected date range.',
                        ),
                      ),
                    ],
                  )
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
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 0,
                                ),
                                selected:
                                    _quickRange == _SalesHistoryQuickRange.today,
                                selectedColor: Colors.lightGreen.shade100,
                                label: const Text('Today'),
                                onSelected: (_) => _setQuickRangeToday(),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 0,
                                ),
                                selected:
                                    _quickRange == _SalesHistoryQuickRange.lastWeek,
                                selectedColor: Colors.lightGreen.shade100,
                                label: const Text('Last week'),
                                onSelected: (_) => _setQuickRangeWeek(),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 0,
                                ),
                                selected:
                                    _quickRange == _SalesHistoryQuickRange.lastMonth,
                                selectedColor: Colors.lightGreen.shade100,
                                label: const Text('Last month'),
                                onSelected: (_) => _setQuickRangeMonth(),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 0,
                                ),
                                selected:
                                    _quickRange == _SalesHistoryQuickRange.all,
                                selectedColor: Colors.lightGreen.shade100,
                                label: const Text('All'),
                                onSelected: (_) => _clearDateRange(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.primary.withValues(alpha: 0.85),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AdaptiveCardText(
                              'Total Amount: $_currencySymbol${formatMoney(_grandTotal)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                            const SizedBox(height: 4),
                            AdaptiveCardText(
                              'Total Amount Paid: $_currencySymbol${formatMoney(_totalPaid)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                            const SizedBox(height: 4),
                            AdaptiveCardText(
                              'Total Balance: $_currencySymbol${formatMoney(_totalBalance)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                            const SizedBox(height: 8),
                            AdaptiveCardText(
                              '$_transactionCount transaction${_transactionCount == 1 ? '' : 's'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                              minFontSize: 10,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AdaptiveCardText(
                              'Total of hardware: $_currencySymbol${formatMoney(_totalOfHardware)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                            const SizedBox(height: 6),
                            AdaptiveCardText(
                              'Total of wholesale: $_currencySymbol${formatMoney(_totalOfWholesale)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                            const SizedBox(height: 6),
                            AdaptiveCardText(
                              'Total of supermarket: $_currencySymbol${formatMoney(_totalOfSupermarket)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                            const SizedBox(height: 6),
                            AdaptiveCardText(
                              'Total of services: $_currencySymbol${formatMoney(_totalOfServices)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              minFontSize: 11,
                            ),
                          ],
                        ),
                      ),
                      if (_dateRange != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text(
                            'Filtered: ${_dateRange!.start.year.toString().padLeft(4, '0')}-${_dateRange!.start.month.toString().padLeft(2, '0')}-${_dateRange!.start.day.toString().padLeft(2, '0')} to ${_dateRange!.end.year.toString().padLeft(4, '0')}-${_dateRange!.end.month.toString().padLeft(2, '0')}-${_dateRange!.end.day.toString().padLeft(2, '0')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visibleReceipts.length + (hasMoreReceipts ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= visibleReceipts.length) {
                            return const Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final receipt = visibleReceipts[index];
                          final saleId = receipt['sale_id'] as int?;
                          final totalAmount = (receipt['total_amount'] as num?)?.toDouble() ?? 0;
                          final overallDiscount =
                              (receipt['overall_discount'] as num?)?.toDouble() ?? 0;
                          final amountReceived = (receipt['amount_received'] as num?)?.toDouble() ?? totalAmount;
                          final balance = (receipt['balance'] as num?)?.toDouble() ?? 0;
                          final customerName = receipt['customer_name'] as String?;
                          final customerPhone = receipt['customer_phone'] as String?;
                          final customerAddress = receipt['customer_address'] as String?;
                          final paymentMethodRaw =
                              (receipt['payment_method'] as String? ?? 'cash')
                                  .trim()
                                  .toLowerCase();
                          final paymentMethodLabel = switch (paymentMethodRaw) {
                            'mobile_money' => 'Mobile Money',
                            'account' => 'Account',
                            _ => 'Cash',
                          };
                          final createdRaw = receipt['created_at'] as String?;
                          final lines = receipt['lines'] as List<Map<String, Object?>>? ?? [];
                          final grandSubtotal = lines.fold<double>(
                            0,
                            (sum, row) => sum + _receiptLineNetTotal(row),
                          );

                          return Card(
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDate(createdRaw),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      if (saleId != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '#$saleId',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              tooltip: 'Export receipt',
                                              visualDensity: VisualDensity.compact,
                                              icon: const Icon(Icons.ios_share, size: 18),
                                              onPressed: () => _exportReceipt(receipt),
                                            ),
                                            IconButton(
                                              tooltip: 'Print receipt',
                                              visualDensity: VisualDensity.compact,
                                              icon: const Icon(Icons.print_outlined, size: 18),
                                              onPressed: () => _printReceipt(receipt),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (customerName != null && customerName.toString().trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: () => _openClientFromReceipt(receipt),
                                      child: Text(
                                        toTitleCaseWords(customerName.toString()),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    if (customerPhone != null && customerPhone.toString().trim().isNotEmpty)
                                      Text(
                                        customerPhone.toString(),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    if (customerAddress != null && customerAddress.toString().trim().isNotEmpty)
                                      Text(
                                        customerAddress.toString(),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    Text(
                                      'Payment: $paymentMethodLabel',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                                    child: Text(
                                      'All amounts in $_currencySymbol',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Table(
                                    defaultVerticalAlignment:
                                        TableCellVerticalAlignment.top,
                                    border: TableBorder(
                                      top: BorderSide(
                                        color: theme.dividerColor,
                                        width: 1,
                                      ),
                                      bottom: BorderSide(
                                        color: theme.dividerColor,
                                        width: 1,
                                      ),
                                      horizontalInside: BorderSide(
                                        color: theme.dividerColor,
                                        width: 1,
                                      ),
                                      left: BorderSide.none,
                                      right: BorderSide.none,
                                      verticalInside: BorderSide.none,
                                    ),
                                    columnWidths: const {
                                      0: FlexColumnWidth(2.35),
                                      1: FlexColumnWidth(1),
                                      2: FlexColumnWidth(1),
                                      3: FlexColumnWidth(1),
                                      4: FlexColumnWidth(1),
                                      5: FlexColumnWidth(1),
                                    },
                                    children: [
                                      TableRow(
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surfaceContainerHighest
                                              .withValues(alpha: 0.35),
                                        ),
                                        children: [
                                          _receiptTableHeader(theme, 'Item'),
                                          _receiptTableHeader(theme, 'Qty'),
                                          _receiptTableHeader(theme, 'Unit sell'),
                                          _receiptTableHeader(theme, 'Subtotal'),
                                          _receiptTableHeader(theme, 'Prod. disc'),
                                          _receiptTableHeader(theme, 'Total'),
                                        ],
                                      ),
                                        ...lines.map((row) {
                                          final name = toTitleCaseWords(
                                            (row['item_name'] as String?) ?? 'Item',
                                          );
                                          final saleCat = _saleCategoryDisplay(
                                            row['item_category'] as String?,
                                          );
                                          final quantity =
                                              (row['quantity'] as num?)?.toDouble() ?? 0;
                                          final unit =
                                              ((row['item_unit'] as String?) ?? '').trim();
                                          final qtyUnit = unit.isEmpty
                                              ? formatDisplayNumber(quantity)
                                              : '${formatDisplayNumber(quantity)} $unit';
                                          final unitSell = _receiptLineUnitSell(row);
                                          final sub = _receiptLineSubtotal(row);
                                          final disc = _receiptLineDiscountApplied(row);
                                          final net = _receiptLineNetTotal(row);
                                          return TableRow(
                                            children: [
                                              _receiptTableCell(
                                                saleCat.isEmpty
                                                    ? Text(
                                                        _receiptUnbreakableSegment(
                                                          name,
                                                        ),
                                                        style: theme
                                                            .textTheme.bodySmall,
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                      )
                                                    : Text.rich(
                                                        TextSpan(
                                                          style: theme
                                                              .textTheme.bodySmall,
                                                          children: [
                                                            TextSpan(
                                                              text:
                                                                  _receiptUnbreakableSegment(
                                                                name,
                                                              ),
                                                            ),
                                                            TextSpan(
                                                              text:
                                                                  '\u00A0–\u00A0${_receiptUnbreakableSegment(saleCat)}',
                                                              style: theme
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                color: Colors
                                                                    .grey
                                                                    .shade700,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                              ),
                                              _receiptTableCell(
                                                Text(
                                                  qtyUnit,
                                                  style: theme.textTheme.bodySmall,
                                                ),
                                              ),
                                              _receiptTableCell(
                                                Text(
                                                  formatMoney(unitSell),
                                                  style: theme.textTheme.bodySmall,
                                                  textAlign: TextAlign.end,
                                                ),
                                                alignEnd: true,
                                              ),
                                              _receiptTableCell(
                                                Text(
                                                  formatMoney(sub),
                                                  style: theme.textTheme.bodySmall,
                                                  textAlign: TextAlign.end,
                                                ),
                                                alignEnd: true,
                                              ),
                                              _receiptTableCell(
                                                Text(
                                                  formatMoney(disc),
                                                  style: theme.textTheme.bodySmall,
                                                  textAlign: TextAlign.end,
                                                ),
                                                alignEnd: true,
                                              ),
                                              _receiptTableCell(
                                                Text(
                                                  formatMoney(net),
                                                  style: theme.textTheme.bodySmall,
                                                  textAlign: TextAlign.end,
                                                ),
                                                alignEnd: true,
                                              ),
                                            ],
                                          );
                                        }),
                                      ],
                                    ),
                                  const SizedBox(height: 8),
                                  _receiptRow(theme, 'Grand subtotal', grandSubtotal),
                                  _receiptRow(theme, 'Overall discount', overallDiscount),
                                  Divider(height: 16, thickness: 1, color: theme.dividerColor),
                                  _receiptRow(
                                    theme,
                                    'Final grand total',
                                    totalAmount,
                                    isEmphasis: true,
                                  ),
                                  Divider(height: 16, thickness: 1, color: theme.dividerColor),
                                  _receiptRow(
                                    theme,
                                    'Amount paid',
                                    amountReceived,
                                    isReceived: true,
                                  ),
                                  _receiptRow(
                                    theme,
                                    'Balance',
                                    balance,
                                    isBalance: balance > 0,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
      ),
    ),
    );
  }
}

enum _SalesHistoryQuickRange { today, lastWeek, lastMonth, all }

