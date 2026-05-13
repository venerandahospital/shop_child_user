import 'package:flutter/material.dart';

import '../models/item.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

class SaleQuantityScreen extends StatefulWidget {
  const SaleQuantityScreen({
    super.key,
    required this.item,
    required this.cartTotal,
    required this.maxAvailable,
    required this.initialQuantity,
    this.initialProductDiscount = '',
    required this.currencySymbol,
    this.sellWholesale = false,
  });

  final Item item;
  final double cartTotal;
  final double maxAvailable;
  final String initialQuantity;
  final String initialProductDiscount;
  final String currencySymbol;

  /// When true, stock and price are per full carton/sack; quantity must be a whole number.
  final bool sellWholesale;

  @override
  State<SaleQuantityScreen> createState() => _SaleQuantityScreenState();
}

class _SaleQuantityScreenState extends State<SaleQuantityScreen> {
  late TextEditingController _controller;
  late TextEditingController _discountController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuantity);
    _controller.addListener(() => setState(() {}));
    final initialDiscount =
        (double.tryParse(widget.initialProductDiscount.replaceAll(',', '.')) ?? 0) > 0
        ? widget.initialProductDiscount
        : '';
    _discountController = TextEditingController(text: initialDiscount);
    _discountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _discountController.dispose();
    super.dispose();
  }

  String get _packUnit {
    final u = (widget.item.unitShort ?? widget.item.unit ?? '').trim();
    return u.isNotEmpty ? u : 'carton';
  }

  /// For wholesale, max sellable is whole packs only.
  double get _effectiveMax {
    if (!widget.sellWholesale) return widget.maxAvailable;
    if (widget.maxAvailable <= 0) return 0;
    return widget.maxAvailable.floorToDouble();
  }

  double get _enteredQty {
    return double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0;
  }

  bool _isWholeNumber(double v) {
    if (v <= 0) return false;
    return (v - v.round()).abs() < 1e-9;
  }

  double get _productSubTotal {
    final qty = _enteredQty;
    if (qty <= 0) return 0;
    return widget.item.sellingPrice * qty;
  }

  double get _enteredProductDiscount {
    return double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0;
  }

  double get _effectiveProductDiscount {
    final discount = _enteredProductDiscount;
    if (discount <= 0) return 0;
    return discount > _productSubTotal ? _productSubTotal : discount;
  }

  double get _productTotal {
    final net = _productSubTotal - _effectiveProductDiscount;
    return net < 0 ? 0 : net;
  }

  double get _overallTotalWithQty {
    return widget.cartTotal + _productTotal;
  }

  String _fmtCompactNumber(double value) {
    return formatDisplayNumber(value);
  }

  void _apply() {
    final raw = _controller.text.replaceAll(',', '.');
    final qty = double.tryParse(raw);
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }
    if (widget.sellWholesale && !_isWholeNumber(qty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wholesale sales use whole ${_packUnit}s only (no partial packs).',
          ),
        ),
      );
      return;
    }
    if (qty > _effectiveMax) {
      final adjusted = widget.sellWholesale
          ? _effectiveMax.floorToDouble()
          : _effectiveMax;
      if (adjusted > 0) {
        _controller.text = adjusted == adjusted.roundToDouble()
            ? adjusted.toInt().toString()
            : formatDisplayNumber(adjusted, fixedDecimals: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough stock. Max is ${formatDisplayNumber(_effectiveMax)}.',
          ),
        ),
      );
      return;
    }
    if (widget.sellWholesale) {
      final i = qty.round();
      _closeAndPop({
        'quantity': i.toString(),
        'productDiscount': _fmtCompactNumber(_effectiveProductDiscount),
      });
      return;
    }
    _closeAndPop({
      'quantity': _controller.text,
      'productDiscount': _fmtCompactNumber(_effectiveProductDiscount),
    });
  }

  void _setQuick(double value) {
    if (widget.sellWholesale) {
      value = value.floorToDouble();
    }
    if (_effectiveMax > 0 && value > _effectiveMax) {
      value = _effectiveMax;
    }
    if (value <= 0) return;
    if (widget.sellWholesale) {
      _controller.text = value.toInt().toString();
    } else {
      _controller.text = value == value.roundToDouble()
          ? value.toInt().toString()
          : formatDisplayNumber(value, fixedDecimals: true);
    }
  }

  void _closeAndPop([Map<String, String>? result]) {
    FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.item.unit ?? '';
    final saleCategory = () {
      final raw = (widget.item.category ?? '').trim();
      if (raw.isEmpty) return '';
      for (final part in raw.split('|').map((p) => p.trim())) {
        if (part.toLowerCase().startsWith('sale:')) {
          return toTitleCaseWords(
            part.substring(part.indexOf(':') + 1).trim(),
          );
        }
      }
      return toTitleCaseWords(raw);
    }();
    final unitLabel = (widget.item.unit ?? widget.item.unitShort ?? '').trim();
    final wholesale = widget.sellWholesale;
    final avUnit = (wholesale ? _packUnit : unit).trim();
    final priceInfoLine =
        'Sell ${widget.currencySymbol}${formatMoney(widget.item.sellingPrice)}'
        '  •  Cost ${widget.currencySymbol}${formatMoney(widget.item.costPrice)}'
        '  •  AV ${formatDisplayNumber(_effectiveMax)}${avUnit.isNotEmpty ? ' $avUnit' : ''}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeAndPop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Quantity'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wholesale) ...[
                Text(
                  "Sell by full cartons or sacks. Set each item's unit to carton or sack in inventory.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                [
                  toTitleCaseWords(widget.item.name),
                  if (saleCategory.isNotEmpty) saleCategory,
                  if (unitLabel.isNotEmpty) toTitleCaseWords(unitLabel),
                ].join(' - '),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                priceInfoLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        keyboardType: wholesale
                            ? const TextInputType.numberWithOptions(
                                signed: false,
                                decimal: false,
                              )
                            : const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          labelText: wholesale
                              ? 'Number of $_packUnit'
                              : 'Quantity${unit.isNotEmpty ? ' ($unit)' : ''}',
                          hintText: wholesale ? 'Whole packs only' : 'Quantity',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _apply,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          wholesale ? 'Set packs' : 'Set quantity',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final quick in [
                    (label: '1', value: 1.0),
                    (label: '2', value: 2.0),
                    (label: '3', value: 3.0),
                    (label: '5', value: 5.0),
                    (label: '10', value: 10.0),
                    (
                      label: 'Max-${formatDisplayNumber(_effectiveMax)}',
                      value: _effectiveMax,
                    ),
                  ]) ...[
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _setQuick(quick.value),
                        child: Container(
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.white,
                          ),
                          child: Text(
                            quick.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (quick !=
                        (
                          label: 'Max-${formatDisplayNumber(_effectiveMax)}',
                          value: _effectiveMax,
                        ))
                      const SizedBox(width: 4),
                  ],
                ],
              ),
              if (_effectiveMax > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Available: ${formatDisplayNumber(_effectiveMax)} $_packUnit',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: TextField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Product discount',
                    prefixText: '${widget.currencySymbol} ',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Product total',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.currencySymbol}${formatMoney(_productTotal)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Overall bill total (with this qty)',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.currencySymbol}${formatMoney(_overallTotalWithQty)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
