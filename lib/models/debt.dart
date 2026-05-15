class Debt {
  final int? id;
  final int? storeId;
  final String customerName;
  final String? phone;
  final String? address;
  final double amount;
  final bool isPaid;
  final DateTime createdAt;

  Debt({
    this.id,
    this.storeId,
    required this.customerName,
    this.phone,
    this.address,
    required this.amount,
    this.isPaid = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Debt.fromMap(Map<String, dynamic> map) {
    return Debt(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      customerName: map['customer_name'] as String? ?? '',
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      isPaid: map['is_paid'] == true || (map['is_paid'] as int? ?? 0) == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'customer_name': customerName,
      'phone': phone,
      'address': address,
      'amount': amount,
      'is_paid': isPaid ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Debt copyWith({
    int? id,
    int? storeId,
    String? customerName,
    String? phone,
    String? address,
    double? amount,
    bool? isPaid,
    DateTime? createdAt,
  }) {
    return Debt(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      amount: amount ?? this.amount,
      isPaid: isPaid ?? this.isPaid,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}



