class Loan {
  final int? id;
  final int? storeId;
  final int clientId;
  final double principalAmount;
  /// Annual interest rate in percent (e.g. 12 = 12% per year).
  final double annualInterestPercent;
  final DateTime expectedPaymentDate;
  /// Simple interest from issue date to expected payment date.
  final double interestAmount;
  final double totalDue;
  final String? note;
  final String status;
  final DateTime createdAt;

  Loan({
    this.id,
    this.storeId,
    required this.clientId,
    required this.principalAmount,
    required this.annualInterestPercent,
    required this.expectedPaymentDate,
    required this.interestAmount,
    required this.totalDue,
    this.note,
    this.status = 'active',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Simple interest: principal × (annual%/100) × (days/365).
  static ({double interest, double total}) computeAccrued({
    required double principal,
    required double annualInterestPercent,
    required DateTime issuedAt,
    required DateTime expectedPaymentDate,
  }) {
    final start = DateTime(issuedAt.year, issuedAt.month, issuedAt.day);
    final end = DateTime(
      expectedPaymentDate.year,
      expectedPaymentDate.month,
      expectedPaymentDate.day,
    );
    var days = end.difference(start).inDays;
    if (days < 0) days = 0;
    final interest =
        principal * (annualInterestPercent / 100.0) * (days / 365.0);
    final total = principal + interest;
    return (interest: interest, total: total);
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    final clientRaw = map['client_id'] ?? map['clientId'];
    return Loan(
      id: map['id'] as int?,
      storeId: map['store_id'] as int? ?? map['storeId'] as int?,
      clientId: clientRaw is int
          ? clientRaw
          : int.tryParse(clientRaw?.toString() ?? '') ?? 0,
      principalAmount:
          (map['principal_amount'] as num? ?? map['principalAmount'] as num?)
                  ?.toDouble() ??
              0,
      annualInterestPercent: (map['annual_interest_percent'] as num? ??
              map['annualInterestPercent'] as num?)
              ?.toDouble() ??
          0,
      expectedPaymentDate: DateTime.tryParse(
            (map['expected_payment_date'] ?? map['expectedPaymentDate'] ?? '')
                .toString(),
          ) ??
          DateTime.now(),
      interestAmount:
          (map['interest_amount'] as num? ?? map['interestAmount'] as num?)
                  ?.toDouble() ??
              0,
      totalDue: (map['total_due'] as num? ?? map['totalDue'] as num?)
              ?.toDouble() ??
          0,
      note: map['note'] as String?,
      status: (map['status'] as String?)?.trim().isNotEmpty == true
          ? (map['status'] as String).trim()
          : 'active',
      createdAt: DateTime.tryParse(
            (map['created_at'] ?? map['createdAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'client_id': clientId,
      'principal_amount': principalAmount,
      'annual_interest_percent': annualInterestPercent,
      'expected_payment_date':
          expectedPaymentDate.toIso8601String().split('T').first,
      'interest_amount': interestAmount,
      'total_due': totalDue,
      'note': note,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toRemoteBody() {
    return {
      if (id != null) 'id': id,
      if (storeId != null) 'storeId': storeId,
      'clientId': clientId,
      'principalAmount': principalAmount,
      'annualInterestPercent': annualInterestPercent,
      'expectedPaymentDate':
          expectedPaymentDate.toIso8601String().split('T').first,
      'interestAmount': interestAmount,
      'totalDue': totalDue,
      'note': note ?? '',
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
