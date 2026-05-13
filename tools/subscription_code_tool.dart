import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    return;
  }

  final command = args.first.toLowerCase();
  final opts = _parseFlags(args.skip(1).toList());
  final secret = (opts['secret'] ?? const String.fromEnvironment('SUBSCRIPTION_CODE_SECRET')).trim();
  if (secret.isEmpty) {
    print(
      'Missing secret. Provide --secret or --dart-define=SUBSCRIPTION_CODE_SECRET=your-secret',
    );
    return;
  }

  switch (command) {
    case 'generate':
      _generate(opts, secret);
      break;
    case 'verify':
      _verify(opts, secret);
      break;
    default:
      _printUsage();
  }
}

void _generate(Map<String, String> opts, String secret) {
  final licenseId = (opts['license'] ?? '').trim();
  final businessCode = (opts['business'] ?? '').trim();
  final owner = (opts['owner'] ?? '').trim();
  final days = int.tryParse((opts['days'] ?? '30').trim()) ?? 30;
  final maxDevices = int.tryParse((opts['max-devices'] ?? '2').trim()) ?? 2;
  if (licenseId.isEmpty) {
    print('Missing --license');
    return;
  }
  if (businessCode.isEmpty) {
    print('Missing --business');
    return;
  }
  if (days <= 0) {
    print('--days must be > 0');
    return;
  }

  final issuedAt = DateTime.now().toUtc();
  final expiresAt = issuedAt.add(Duration(days: days));
  final payload = <String, dynamic>{
    'v': 1,
    'type': 'monthly_subscription',
    'licenseId': licenseId,
    'businessCode': businessCode,
    'owner': owner,
    'maxDevices': maxDevices,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'nonce': _randomToken(18),
  };

  final payloadJson = jsonEncode(payload);
  final payloadB64 = _b64UrlNoPad(utf8.encode(payloadJson));
  final sigB64 = _sign(payloadB64, secret);
  final code = 'LABSUB1.$payloadB64.$sigB64';

  print('Activation code generated:\n');
  print(code);
  print('\n---');
  print('License ID : $licenseId');
  print('Business   : $businessCode');
  print('Owner      : ${owner.isEmpty ? '-' : owner}');
  print('Max devices: $maxDevices');
  print('Issued UTC : ${payload['issuedAt']}');
  print('Expires UTC: ${payload['expiresAt']}');
  print('Days       : $days');
}

void _verify(Map<String, String> opts, String secret) {
  final code = (opts['code'] ?? '').trim();
  if (code.isEmpty) {
    print('Missing --code');
    return;
  }

  final parsed = _parseAndValidate(code: code, secret: secret);
  if (!parsed.ok) {
    print('INVALID: ${parsed.message}');
    return;
  }
  final payload = parsed.payload!;
  final expiresAt = DateTime.tryParse('${payload['expiresAt']}')?.toUtc();
  final now = DateTime.now().toUtc();
  final expired = expiresAt == null || !expiresAt.isAfter(now);
  final daysLeft = expiresAt == null ? 0 : expiresAt.difference(now).inDays;

  print('VALID');
  print('License ID : ${payload['licenseId']}');
  print('Business   : ${payload['businessCode'] ?? '-'}');
  print('Owner      : ${payload['owner'] ?? '-'}');
  print('Max devices: ${payload['maxDevices'] ?? 2}');
  print('Issued UTC : ${payload['issuedAt']}');
  print('Expires UTC: ${payload['expiresAt']}');
  print('Expired    : ${expired ? 'YES' : 'NO'}');
  print('Days left  : ${expired ? 0 : daysLeft}');
}

({bool ok, String message, Map<String, dynamic>? payload}) _parseAndValidate({
  required String code,
  required String secret,
}) {
  final parts = code.split('.');
  if (parts.length != 3 || parts.first != 'LABSUB1') {
    return (ok: false, message: 'Invalid code format.', payload: null);
  }
  final payloadB64 = parts[1];
  final providedSig = parts[2];
  final expectedSig = _sign(payloadB64, secret);
  if (!_constantTimeEquals(providedSig, expectedSig)) {
    return (ok: false, message: 'Signature mismatch.', payload: null);
  }
  try {
    final payloadBytes = _b64UrlDecodeNoPad(payloadB64);
    final payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
    return (ok: true, message: 'OK', payload: payload);
  } catch (_) {
    return (ok: false, message: 'Corrupted payload.', payload: null);
  }
}

String _sign(String payloadB64, String secret) {
  final hmac = Hmac(sha256, utf8.encode(secret));
  final digest = hmac.convert(utf8.encode(payloadB64));
  return _b64UrlNoPad(digest.bytes);
}

String _randomToken(int len) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(len, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
}

String _b64UrlNoPad(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

List<int> _b64UrlDecodeNoPad(String input) {
  final padLen = (4 - input.length % 4) % 4;
  final padded = input + ('=' * padLen);
  return base64Url.decode(padded);
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}

Map<String, String> _parseFlags(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final token = args[i];
    if (!token.startsWith('--')) continue;
    final key = token.substring(2);
    final next = (i + 1) < args.length ? args[i + 1] : '';
    if (next.startsWith('--') || next.isEmpty) {
      out[key] = 'true';
      continue;
    }
    out[key] = next;
    i++;
  }
  return out;
}

void _printUsage() {
  print('''
Subscription Code Tool

Generate:
  dart run tools/subscription_code_tool.dart generate --license SHOP-001 --business BUS-001 --owner "Client Name" --days 30 --max-devices 2 --secret your-secret

Verify:
  dart run tools/subscription_code_tool.dart verify --code LABSUB1.... --secret your-secret
''');
}

