class Unit {
  final int? id;
  final String unitName;
  final String unitShortName;

  const Unit({
    this.id,
    required this.unitName,
    required this.unitShortName,
  });

  /// Display for dropdown: "Unit Name (short)"
  String get displayLabel => '$unitName ($unitShortName)';

  factory Unit.fromMap(Map<String, dynamic> map) {
    return Unit(
      id: map['id'] as int?,
      unitName: map['unit_name'] as String? ?? '',
      unitShortName: map['unit_short_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'unit_name': unitName,
      'unit_short_name': unitShortName,
    };
  }
}
