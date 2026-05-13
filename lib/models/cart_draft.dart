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
}
