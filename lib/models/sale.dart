class Sale {
  final int? id;
  final int? storeId;
  final double totalAmount;
  final double overallDiscount;
  final double? amountReceived;
  final double? balance;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String paymentMethod;
  final DateTime createdAt;

  Sale({
    this.id,
    this.storeId,
    required this.totalAmount,
    this.overallDiscount = 0,
    this.amountReceived,
    this.balance,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.paymentMethod = 'cash',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Sale.fromMap(Map<String, dynamic> map) {
    final total = (map['total_amount'] as num?)?.toDouble() ?? 0;
    final received = map['amount_received'] != null
        ? (map['amount_received'] as num?)?.toDouble()
        : null;
    final bal = map['balance'] != null
        ? (map['balance'] as num?)?.toDouble()
        : null;
    return Sale(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      totalAmount: total,
      overallDiscount: (map['overall_discount'] as num?)?.toDouble() ?? 0,
      amountReceived: received ?? total,
      balance: bal ?? 0,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      customerAddress: map['customer_address'] as String?,
      paymentMethod: (map['payment_method'] as String?)?.trim().isNotEmpty == true
          ? (map['payment_method'] as String).trim()
          : 'cash',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'total_amount': totalAmount,
      'overall_discount': overallDiscount,
      'amount_received': amountReceived ?? totalAmount,
      'balance': balance ?? 0,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'payment_method': paymentMethod.trim().isEmpty ? 'cash' : paymentMethod.trim(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}



