class CartDraft {
  final int id;
  final String title;
  final String payloadJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CartDraft({
    required this.id,
    required this.title,
    required this.payloadJson,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CartDraft.fromMap(Map<String, Object?> m) {
    return CartDraft(
      id: m['id']! as int,
      title: m['title']! as String,
      payloadJson: m['payload']! as String,
      createdAt: DateTime.parse(m['created_at']! as String),
      updatedAt: DateTime.parse(m['updated_at']! as String),
    );
  }

  /// Parses JSON from mother's `GET /cart-drafts`.
  factory CartDraft.fromRemoteJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int ? idRaw : int.parse(idRaw.toString());
    final payload = json['payload'] ?? json['payloadJson'];
    final payloadStr = payload is String
        ? payload
        : (payload == null ? '{}' : payload.toString());
    final createdRaw = json['created_at'] ?? json['createdAt'];
    final updatedRaw = json['updated_at'] ?? json['updatedAt'];
    return CartDraft(
      id: id,
      title: (json['title'] ?? '').toString(),
      payloadJson: payloadStr,
      createdAt:
          DateTime.tryParse((createdRaw ?? '').toString()) ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse((updatedRaw ?? '').toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'id': id,
      'title': title,
      'payload': payloadJson,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
