import 'package:flutter/material.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';

class SaleAmountReceivedScreen extends StatefulWidget {
  const SaleAmountReceivedScreen({
    super.key,
    required this.totalAmount,
    required this.initialAmount,
    required this.currencySymbol,
  });

  final double totalAmount;
  final String initialAmount;
  final String currencySymbol;

  @override
  State<SaleAmountReceivedScreen> createState() =>
      _SaleAmountReceivedScreenState();
}

class _SaleAmountReceivedScreenState extends State<SaleAmountReceivedScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAmount);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _enteredAmount {
    return double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0;
  }

  double get _balance => widget.totalAmount - _enteredAmount;

  void _closeAndPop([String? result]) {
    FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  void _apply() {
    final amount = _enteredAmount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    if (amount > widget.totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paid amount cannot be more than total'),
        ),
      );
      return;
    }
    _closeAndPop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeAndPop();
      },
      child: Scaffold(
      appBar: AppBar(title: const SectionPageTitle(pageTitle: 'Paid')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
                        'Total',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.currencySymbol}${formatMoney(widget.totalAmount)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Paid',
                  prefixText: '${widget.currencySymbol} ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_enteredAmount > 0 && _enteredAmount <= widget.totalAmount) ...[
                const SizedBox(height: 16),
                Card(
                  color: _balance > 0
                      ? Colors.orange.shade50
                      : Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Balance (debt)',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.currencySymbol}${formatMoney(_balance)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _balance > 0 ? Colors.orange.shade900 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
