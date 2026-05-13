import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class TransactionsService {
  final _auth = AuthService();

  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    final token = await _auth.getToken();
    final baseUrl = await _auth.getBaseUrl();
    final res = await http.get(
      Uri.parse('$baseUrl/transactions'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return <Map<String, dynamic>>[];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rows = (body['data'] as List<dynamic>? ?? <dynamic>[]);
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<bool> createTransaction({
    required String description,
    required double amount,
  }) async {
    final token = await _auth.getToken();
    final baseUrl = await _auth.getBaseUrl();
    final res = await http.post(
      Uri.parse('$baseUrl/transactions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'description': description, 'amount': amount}),
    );
    return res.statusCode == 201;
  }
}
