class DebtPayment {
  final int? id;
  final int? storeId;
  final String customerName;
  final double paidAmount;
  final double remainingBalance;
  final DateTime createdAt;

  DebtPayment({
    this.id,
    this.storeId,
    required this.customerName,
    required this.paidAmount,
    required this.remainingBalance,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory DebtPayment.fromMap(Map<String, dynamic> map) {
    return DebtPayment(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      customerName: map['customer_name'] as String? ?? '',
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      remainingBalance: (map['remaining_balance'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'customer_name': customerName,
      'paid_amount': paidAmount,
      'remaining_balance': remainingBalance,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

