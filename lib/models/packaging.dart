class Packaging {
  final int? id;
  final String name;
  final String? shortName;

  const Packaging({
    this.id,
    required this.name,
    this.shortName,
  });

  String get displayLabel {
    final s = (shortName ?? '').trim();
    return s.isEmpty ? name : '$name ($s)';
  }

  factory Packaging.fromMap(Map<String, dynamic> map) {
    return Packaging(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      shortName: map['short_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'short_name': shortName,
    };
  }
}

