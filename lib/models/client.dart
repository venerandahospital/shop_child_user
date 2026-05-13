class Client {
  final int? id;
  final int? storeId;
  final String name;
  final String? phone;
  final String? address;
  final DateTime createdAt;

  Client({
    this.id,
    this.storeId,
    required this.name,
    this.phone,
    this.address,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as int?,
      storeId: map['store_id'] as int?,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'phone': phone,
      'address': address,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Client copyWith({
    int? id,
    int? storeId,
    String? name,
    String? phone,
    String? address,
    DateTime? createdAt,
  }) {
    return Client(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

