class Asset {
  final int? id;
  final int? storeId;
  final String name;
  final double purchaseCost;
  final double currentValue;
  final DateTime purchaseDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Asset({
    this.id,
    this.storeId,
    required this.name,
    required this.purchaseCost,
    required this.currentValue,
    required this.purchaseDate,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Asset.fromMap(Map<String, dynamic> map) {
    return Asset(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      name: map['name'] as String? ?? '',
      purchaseCost: (map['purchase_cost'] as num?)?.toDouble() ?? 0,
      currentValue: (map['current_value'] as num?)?.toDouble() ?? 0,
      purchaseDate:
          DateTime.tryParse((map['purchase_date'] as String?) ?? '') ??
              DateTime.now(),
      notes: map['notes'] as String?,
      createdAt:
          DateTime.tryParse((map['created_at'] as String?) ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'purchase_cost': purchaseCost,
      'current_value': currentValue,
      'purchase_date': purchaseDate.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
