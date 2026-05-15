import 'package:flutter/material.dart';

import 'text_format.dart';

/// After a sale: is this roll/piece still on the shelf? Yes = leave stock at hand
/// unchanged. No = set stock at hand to 0.
Future<bool> showSpecialItemAvailabilityDialog(
  BuildContext context, {
  required String itemName,
}) async {
  final label = toTitleCaseWords(itemName);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Special item'),
      content: Text('Is "$label" still available?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  // Only explicit Yes keeps stock at 1; No (or dismiss) marks out of stock.
  return result == true;
}
