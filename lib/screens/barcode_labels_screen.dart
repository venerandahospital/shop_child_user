import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/item.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

class BarcodeLabelsScreen extends StatefulWidget {
  const BarcodeLabelsScreen({super.key, required this.items});

  final List<Item> items;

  @override
  State<BarcodeLabelsScreen> createState() => _BarcodeLabelsScreenState();
}

class _BarcodeLabelsScreenState extends State<BarcodeLabelsScreen> {
  String _saleCategoryLabel(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return 'Uncategorized';
    for (final part in raw.split('|').map((e) => e.trim())) {
      if (part.toLowerCase().startsWith('sale:')) {
        return toTitleCaseWords(part.substring(part.indexOf(':') + 1).trim());
      }
    }
    return toTitleCaseWords(raw);
  }

  String _labelTitle(Item item) {
    final name = toTitleCaseWords(item.name);
    final saleCategory = _saleCategoryLabel(item);
    final unitName = ((item.unit ?? '').trim().isEmpty ? 'Unit' : item.unit!.trim());
    return '$name - $saleCategory - $unitName';
  }

  static final RegExp _autoSkuPattern = RegExp(r'^ITM\d{6}$');
  final Map<int, int> _copiesByItemId = <int, int>{};

  String _primaryCode(Item item) {
    final sku = (item.sku ?? '').trim().toUpperCase();
    if (_autoSkuPattern.hasMatch(sku)) return sku;
    return '';
  }

  List<Item> get _labelItems {
    final source = widget.items.where((item) {
      final code = _primaryCode(item);
      return code.isNotEmpty;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return source;
  }

  int _copiesFor(Item item) {
    final key = item.id ?? item.hashCode;
    return _copiesByItemId[key] ?? 1;
  }

  void _setCopies(Item item, int value) {
    final key = item.id ?? item.hashCode;
    setState(() {
      _copiesByItemId[key] = value.clamp(1, 99);
    });
  }

  List<({Item item, String code})> _expandedLabels() {
    final labels = <({Item item, String code})>[];
    for (final item in _labelItems) {
      final code = _primaryCode(item);
      if (code.isEmpty) continue;
      final copies = _copiesFor(item);
      for (var i = 0; i < copies; i++) {
        labels.add((item: item, code: code));
      }
    }
    return labels;
  }

  Future<Uint8List> _buildPdf() async {
    final labels = _expandedLabels();
    final doc = pw.Document();

    const cols = 3;
    const rows = 8;
    const perPage = cols * rows;
    final pageCount = (labels.length / perPage).ceil();

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final start = pageIndex * perPage;
      final end = (start + perPage).clamp(0, labels.length);
      final pageLabels = labels.sublist(start, end);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(14),
          build: (context) {
            return pw.GridView(
              crossAxisCount: cols,
              childAspectRatio: 2.1,
              children: pageLabels.map((entry) {
                return pw.Container(
                  margin: const pw.EdgeInsets.all(4),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        _labelTitle(entry.item),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Sell: ${formatMoney(entry.item.sellingPrice)}',
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Expanded(
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: entry.code,
                          drawText: false,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        entry.code,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    }

    return doc.save();
  }

  Future<void> _printLabels() async {
    final labels = _expandedLabels();
    if (labels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barcode labels selected to print.')),
      );
      return;
    }

    await Printing.layoutPdf(
      name: 'barcode-labels',
      onLayout: (_) => _buildPdf(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _labelItems;
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Print barcode labels'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} items • ${_expandedLabels().length} labels',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _printLabels,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No items with barcode found for current filter.'),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final code = _primaryCode(item);
                      final copies = _copiesFor(item);
                      return ListTile(
                        title: Text(toTitleCaseWords(item.name)),
                        subtitle: Text(code),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Less copies',
                              onPressed: () => _setCopies(item, copies - 1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '$copies',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: 'More copies',
                              onPressed: () => _setCopies(item, copies + 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
