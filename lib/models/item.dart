class Item {
  final int? id;
  final int? storeId;
  final String name;
  final String? sku;
  /// Product barcode (EAN/UPC etc.). Kept separate from internal [sku].
  final String? barcode;
  final String? category;
  final String? unit;
  final String? unitShort;
  final String? shelfNumber;
  final String? imageUrl;
  final String? imageUrl2;
  final String? imageUrl3;
  final int? packagingId;
  final String? variantGroup;
  final double? unitsPerPackage;
  final double costPrice;
  final double sellingPrice;
  final double stockQty;
  final double reorderLevel;
  final double restockTo;
  final double specialRollMetersTotal;
  final double specialRollMetersSold;
  final DateTime createdAt;

  Item({
    this.id,
    this.storeId,
    required this.name,
    this.sku,
    this.barcode,
    this.category,
    this.unit,
    this.unitShort,
    this.shelfNumber,
    this.imageUrl,
    this.imageUrl2,
    this.imageUrl3,
    this.packagingId,
    this.variantGroup,
    this.unitsPerPackage,
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.stockQty = 0,
    this.reorderLevel = 0,
    this.restockTo = 0,
    this.specialRollMetersTotal = 0,
    this.specialRollMetersSold = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get specialRollMetersRemaining {
    final left = specialRollMetersTotal - specialRollMetersSold;
    return left < 0 ? 0 : left;
  }

  bool get isOutOfStock => stockQty <= 0;

  bool get isBelowReorder => stockQty <= reorderLevel;

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      name: map['name'] as String? ?? '',
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      category: map['category'] as String?,
      unit: map['unit'] as String?,
      unitShort: map['unit_short'] as String?,
      shelfNumber: map['shelf_number'] as String? ?? map['shelfNumber'] as String?,
      imageUrl: map['image_url'] as String? ?? map['imageUrl'] as String?,
      imageUrl2: map['image_url_2'] as String? ?? map['imageUrl2'] as String?,
      imageUrl3: map['image_url_3'] as String? ?? map['imageUrl3'] as String?,
      packagingId: map['packaging_id'] as int?,
      variantGroup: map['variant_group'] as String?,
      unitsPerPackage: (map['units_per_package'] as num?)?.toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      stockQty: (map['stock_qty'] as num?)?.toDouble() ?? 0,
      reorderLevel: (map['reorder_level'] as num?)?.toDouble() ?? 0,
      restockTo: (map['restock_to'] as num?)?.toDouble() ?? 0,
      specialRollMetersTotal:
          (map['special_roll_meters_total'] as num?)?.toDouble() ??
          (map['specialRollMetersTotal'] as num?)?.toDouble() ??
          0,
      specialRollMetersSold:
          (map['special_roll_meters_sold'] as num?)?.toDouble() ??
          (map['specialRollMetersSold'] as num?)?.toDouble() ??
          0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'category': category,
      'unit': unit,
      'unit_short': unitShort,
      'shelf_number': shelfNumber,
      'image_url': imageUrl,
      'image_url_2': imageUrl2,
      'image_url_3': imageUrl3,
      'packaging_id': packagingId,
      'variant_group': variantGroup,
      'units_per_package': unitsPerPackage,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'stock_qty': stockQty,
      'reorder_level': reorderLevel,
      'restock_to': restockTo,
      'special_roll_meters_total': specialRollMetersTotal,
      'special_roll_meters_sold': specialRollMetersSold,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Item copyWith({
    int? id,
    int? storeId,
    String? name,
    String? sku,
    String? barcode,
    String? category,
    String? unit,
    String? unitShort,
    String? shelfNumber,
    String? imageUrl,
    String? imageUrl2,
    String? imageUrl3,
    int? packagingId,
    String? variantGroup,
    double? unitsPerPackage,
    double? costPrice,
    double? sellingPrice,
    double? stockQty,
    double? reorderLevel,
    double? restockTo,
    double? specialRollMetersTotal,
    double? specialRollMetersSold,
    DateTime? createdAt,
  }) {
    return Item(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      unitShort: unitShort ?? this.unitShort,
      shelfNumber: shelfNumber ?? this.shelfNumber,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrl2: imageUrl2 ?? this.imageUrl2,
      imageUrl3: imageUrl3 ?? this.imageUrl3,
      packagingId: packagingId ?? this.packagingId,
      variantGroup: variantGroup ?? this.variantGroup,
      unitsPerPackage: unitsPerPackage ?? this.unitsPerPackage,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      stockQty: stockQty ?? this.stockQty,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      restockTo: restockTo ?? this.restockTo,
      specialRollMetersTotal:
          specialRollMetersTotal ?? this.specialRollMetersTotal,
      specialRollMetersSold:
          specialRollMetersSold ?? this.specialRollMetersSold,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
