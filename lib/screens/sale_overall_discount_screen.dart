import 'package:flutter/material.dart';

import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';

class SaleOverallDiscountScreen extends StatefulWidget {
  const SaleOverallDiscountScreen({
    super.key,
    required this.cartSubtotal,
    required this.initialDiscountText,
    required this.currencySymbol,
  });

  final double cartSubtotal;
  final String initialDiscountText;
  final String currencySymbol;

  @override
  State<SaleOverallDiscountScreen> createState() =>
      _SaleOverallDiscountScreenState();
}

class _SaleOverallDiscountScreenState extends State<SaleOverallDiscountScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDiscountText.trim());
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _entered {
    return double.tryParse(_controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  double get _effectiveDiscount {
    return _entered.clamp(0, widget.cartSubtotal).toDouble();
  }

  double get _remaining {
    return (widget.cartSubtotal - _effectiveDiscount)
        .clamp(0, double.infinity)
        .toDouble();
  }

  void _closeCancel() {
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;
      navigator.pop<double?>(null);
    });
  }

  void _apply() {
    if (!_formKey.currentState!.validate()) return;
    final parsed = double.parse(
      _controller.text.trim().replaceAll(',', '.'),
    );
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;
      navigator.pop<double?>(parsed);
    });
  }

  String _fmtMoney(double value) => formatMoney(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const SectionPageTitle(pageTitle: 'Overall discount'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cart subtotal',
                            style: theme.textTheme.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.currencySymbol}${_fmtMoney(widget.cartSubtotal)}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Discount',
                      prefixText: '${widget.currencySymbol} ',
                    ),
                    validator: (raw) {
                      final text = (raw ?? '').trim();
                      if (text.isEmpty) return 'Enter discount';
                      final parsed = double.tryParse(text.replaceAll(',', '.'));
                      if (parsed == null) return 'Enter a valid number';
                      if (parsed < 0) return 'Discount cannot be negative';
                      if (parsed > widget.cartSubtotal) {
                        return 'Max is ${widget.currencySymbol}${_fmtMoney(widget.cartSubtotal)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Remaining total',
                            style: theme.textTheme.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.currencySymbol}${_fmtMoney(_remaining)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
