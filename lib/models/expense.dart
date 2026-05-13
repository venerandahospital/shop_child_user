class Expense {
  final int? id;
  final int? storeId;
  final String title;
  final String? category;
  final String? paidBy;
  final String? receivedBy;
  final String? notes;
  final double amount;
  final DateTime createdAt;

  Expense({
    this.id,
    this.storeId,
    required this.title,
    this.category,
    this.paidBy,
    this.receivedBy,
    this.notes,
    required this.amount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      title: map['title'] as String? ?? '',
      category: map['category'] as String?,
      paidBy: map['paid_by'] as String?,
      receivedBy: map['received_by'] as String?,
      notes: map['notes'] as String?,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'title': title,
      'category': category,
      'paid_by': paidBy,
      'received_by': receivedBy,
      'notes': notes,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

