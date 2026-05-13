import 'package:flutter/material.dart';

import '../utils/number_display.dart';

class SaleAccountPaymentScreen extends StatelessWidget {
  const SaleAccountPaymentScreen({
    super.key,
    required this.clientName,
    required this.currencySymbol,
    required this.totalAmount,
    required this.availableBalance,
  });

  final String clientName;
  final String currencySymbol;
  final double totalAmount;
  final double availableBalance;

  @override
  Widget build(BuildContext context) {
    final payable = availableBalance <= 0
        ? 0.0
        : (availableBalance >= totalAmount ? totalAmount : availableBalance);
    final modeLabel = payable >= totalAmount
        ? 'All payment'
        : payable > 0
            ? 'Partial payment'
            : 'Zero payment';
    return Scaffold(
      appBar: AppBar(title: const Text('Client account payment')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              clientName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Available account balance: $currencySymbol${formatMoney(availableBalance)}',
                    ),
                    const SizedBox(height: 6),
                    Text('Sale total: $currencySymbol${formatMoney(totalAmount)}'),
                    const SizedBox(height: 6),
                    Text(
                      'Money to pay: $currencySymbol${formatMoney(payable)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Payment mode: $modeLabel'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(payable),
              child: const Text('Use this amount'),
            ),
          ],
        ),
      ),
    );
  }
}

