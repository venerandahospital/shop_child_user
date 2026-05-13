class StockReceipt {
  final int? id;
  final int? storeId;
  final int itemId;
  final double quantity;
  final double unitCost;
  final double totalCost;
  final double unitSell;
  final double oldQty;
  final double newQty;
  final String? brand;
  final DateTime? expiryDate;
  final DateTime receivedAt;

  StockReceipt({
    this.id,
    this.storeId,
    required this.itemId,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    required this.unitSell,
    required this.oldQty,
    required this.newQty,
    this.brand,
    this.expiryDate,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'item_id': itemId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      'unit_sell': unitSell,
      'old_qty': oldQty,
      'new_qty': newQty,
      'brand': brand,
      'expiry_date': expiryDate?.toIso8601String(),
      'received_at': receivedAt.toIso8601String(),
    };
  }

  factory StockReceipt.fromMap(Map<String, dynamic> map) {
    return StockReceipt(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      itemId: map['item_id'] as int,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      unitSell: (map['unit_sell'] as num?)?.toDouble() ?? 0,
      oldQty: (map['old_qty'] as num?)?.toDouble() ?? 0,
      newQty: (map['new_qty'] as num?)?.toDouble() ?? 0,
      brand: map['brand'] as String?,
      expiryDate: map['expiry_date'] != null
          ? DateTime.tryParse(map['expiry_date'] as String)
          : null,
      receivedAt: DateTime.tryParse(
            map['received_at'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }
}

