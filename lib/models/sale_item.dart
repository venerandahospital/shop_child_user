class SaleItem {
  final int? id;
  final int? saleId;
  final int itemId;
  final double quantity;
  final double unitPrice;
  final double productDiscount;

  SaleItem({
    this.id,
    this.saleId,
    required this.itemId,
    required this.quantity,
    required this.unitPrice,
    this.productDiscount = 0,
  });

  double get lineTotal => quantity * unitPrice;
  double get netLineTotal {
    final net = lineTotal - productDiscount;
    return net < 0 ? 0 : net;
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'] as int?,
      saleId: map['sale_id'] as int?,
      itemId: map['item_id'] as int? ?? 0,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      productDiscount: (map['product_discount'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sale_id': saleId,
      'item_id': itemId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'product_discount': productDiscount,
      'line_total': lineTotal,
    };
  }
}



