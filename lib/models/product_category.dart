class ProductCategory {
  final int? id;
  final String mainCategory;
  final String subCategory;

  const ProductCategory({
    this.id,
    required this.mainCategory,
    required this.subCategory,
  });

  /// Display string for dropdown: "Main - Sub"
  String get displayLabel => '$mainCategory - $subCategory';

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id'] as int?,
      mainCategory: map['main_category'] as String? ?? '',
      subCategory: map['sub_category'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'main_category': mainCategory,
      'sub_category': subCategory,
    };
  }
}
