class ExpenseCategory {
  final int? id;
  final String name;
  final int? parentId;
  /// Full path from root to this category (e.g. "Office > Furniture > Chairs"). Set when loading.
  final String? path;

  const ExpenseCategory({
    this.id,
    required this.name,
    this.parentId,
    this.path,
  });

  /// Display for dropdown and list: full path if set, otherwise name.
  String get displayLabel => (path != null && path!.isNotEmpty) ? path! : name;

  /// Depth in hierarchy (0 = top-level). Requires path to be set.
  int get depth => path != null ? path!.split(' > ').length - 1 : 0;

  factory ExpenseCategory.fromMap(Map<String, dynamic> map) {
    return ExpenseCategory(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      parentId: map['parent_id'] as int?,
      path: null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
    };
  }

  ExpenseCategory copyWith({int? id, String? name, int? parentId, String? path}) {
    return ExpenseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      path: path ?? this.path,
    );
  }
}
