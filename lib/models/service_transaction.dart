class ServiceTransaction {
  final int? id;
  final int? storeId;
  final String title;
  final String? notes;
  final double amount;
  final DateTime createdAt;

  ServiceTransaction({
    this.id,
    this.storeId,
    required this.title,
    this.notes,
    required this.amount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ServiceTransaction.fromMap(Map<String, dynamic> map) {
    return ServiceTransaction(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      title: map['title'] as String? ?? '',
      notes: map['notes'] as String?,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'title': title,
      'notes': notes,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
