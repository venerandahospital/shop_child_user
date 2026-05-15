import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'local_db_service.dart';

class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const _kActivatedAt = 'subscriptionActivatedAt';
  static const _kExpiresAt = 'subscriptionExpiresAt';
  static const _kLastReminderDate = 'subscriptionLastReminderDate';
  static const _kBusinessCode = 'subscriptionBusinessCode';
  static const _kDeviceId = 'subscriptionDeviceId';
  static const _secret = String.fromEnvironment(
    'SUBSCRIPTION_CODE_SECRET',
    defaultValue: 'demo-secret-123',
  );
  static const _uuid = Uuid();
  static const _metaActivatedAt = 'subscription_activated_at';
  static const _metaExpiresAt = 'subscription_expires_at';
  static const _metaLastReminderDate = 'subscription_last_reminder_date';
  static const _metaBusinessCode = 'subscription_business_code';

  Future<String> _readMetaWithPrefsFallback(
    SharedPreferences prefs,
    String metaKey,
    String prefsKey,
  ) async {
    final fromDb = (await LocalDbService.instance.getAppMeta(metaKey) ?? '').trim();
    if (fromDb.isNotEmpty) return fromDb;
    final fromPrefs = (prefs.getString(prefsKey) ?? '').trim();
    if (fromPrefs.isNotEmpty) {
      await LocalDbService.instance.setAppMeta(metaKey, fromPrefs);
    }
    return fromPrefs;
  }

  Future<SubscriptionStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    final activatedRaw = await _readMetaWithPrefsFallback(
      prefs,
      _metaActivatedAt,
      _kActivatedAt,
    );
    final expiresRaw = await _readMetaWithPrefsFallback(
      prefs,
      _metaExpiresAt,
      _kExpiresAt,
    );
    final isActivated = activatedRaw.isNotEmpty && expiresRaw.isNotEmpty;
    if (!isActivated) {
      return SubscriptionStatus(
        activatedAt: now,
        expiresAt: now,
        expired: true,
        daysLeft: 0,
        daysUsed: 0,
        inReminderWindow: false,
        isActivated: false,
      );
    }
    final activatedAt = DateTime.tryParse(activatedRaw)?.toUtc() ?? now;
    final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc() ?? now;

    final expired = !expiresAt.isAfter(now);
    final daysLeftRaw = expiresAt.difference(now).inDays;
    final daysLeft = daysLeftRaw < 0 ? 0 : daysLeftRaw;
    final totalDays = expiresAt.difference(activatedAt).inDays <= 0
        ? 30
        : expiresAt.difference(activatedAt).inDays;
    final daysUsed = totalDays - daysLeft;
    final inReminderWindow = !expired && daysUsed >= 25;

    return SubscriptionStatus(
      activatedAt: activatedAt,
      expiresAt: expiresAt,
      expired: expired,
      daysLeft: daysLeft,
      daysUsed: daysUsed,
      inReminderWindow: inReminderWindow,
      isActivated: true,
    );
  }

  Future<bool> shouldShowReminderToday() async {
    final status = await getStatus();
    if (!status.isActivated || status.expired) return false;
    final urgentFewDaysLeft = status.daysLeft <= 2;
    if (!status.inReminderWindow && !urgentFewDaysLeft) return false;
    final prefs = await SharedPreferences.getInstance();
    final today = _ymd(DateTime.now().toUtc());
    final last = await _readMetaWithPrefsFallback(
      prefs,
      _metaLastReminderDate,
      _kLastReminderDate,
    );
    return last != today;
  }

  Future<void> markReminderShownToday() async {
    final today = _ymd(DateTime.now().toUtc());
    await LocalDbService.instance.setAppMeta(_metaLastReminderDate, today);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastReminderDate, today);
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_kDeviceId) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final created = _uuid.v4();
    await prefs.setString(_kDeviceId, created);
    return created;
  }

  Future<ActivationResult> activateWithCode({
    required String code,
    required String businessCode,
  }) async {
    final parsed = _parseAndValidate(code.trim());
    if (!parsed.ok) {
      return ActivationResult(ok: false, message: parsed.message);
    }
    final payload = parsed.payload!;
    final expiresAt = DateTime.tryParse('${payload['expiresAt']}')?.toUtc();
    if (expiresAt == null) {
      return const ActivationResult(ok: false, message: 'Code has invalid expiry date.');
    }
    final now = DateTime.now().toUtc();
    if (!expiresAt.isAfter(now)) {
      return const ActivationResult(ok: false, message: 'Code is already expired.');
    }
    final payloadBusinessCode = ('${payload['businessCode'] ?? ''}').trim();
    if (payloadBusinessCode.isEmpty) {
      return const ActivationResult(
        ok: false,
        message: 'Code is missing business code.',
      );
    }
    if (payloadBusinessCode.toLowerCase() != businessCode.trim().toLowerCase()) {
      return const ActivationResult(
        ok: false,
        message: 'Business code does not match this activation code.',
      );
    }

    final activatedAt =
        DateTime.tryParse('${payload['issuedAt']}')?.toUtc() ?? now;
    await LocalDbService.instance.setAppMeta(
      _metaActivatedAt,
      activatedAt.toIso8601String(),
    );
    await LocalDbService.instance.setAppMeta(
      _metaExpiresAt,
      expiresAt.toIso8601String(),
    );
    await LocalDbService.instance.setAppMeta(_metaBusinessCode, payloadBusinessCode);
    await LocalDbService.instance.setAppMeta(_metaLastReminderDate, '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActivatedAt, activatedAt.toIso8601String());
    await prefs.setString(_kExpiresAt, expiresAt.toIso8601String());
    await prefs.setString(_kBusinessCode, payloadBusinessCode);
    await getOrCreateDeviceId();
    await prefs.remove(_kLastReminderDate);
    final maxDevices = (payload['maxDevices'] as num?)?.toInt() ?? 2;
    final warning = maxDevices <= 2
        ? ' Note: phone-limit (max 2) must be enforced by backend/shared registry.'
        : '';
    return ActivationResult(
      ok: true,
      message: 'Subscription activated.$warning',
    );
  }

  ({bool ok, String message, Map<String, dynamic>? payload}) _parseAndValidate(
    String code,
  ) {
    final parts = code.split('.');
    if (parts.length != 3 || parts[0] != 'LABSUB1') {
      return (ok: false, message: 'Invalid activation code format.', payload: null);
    }
    final payloadB64 = parts[1];
    final signature = parts[2];
    final expectedSignature = _sign(payloadB64, _secret);
    if (!_constantTimeEquals(signature, expectedSignature)) {
      return (ok: false, message: 'Activation code signature is invalid.', payload: null);
    }

    try {
      final payloadJson = utf8.decode(_b64UrlDecodeNoPad(payloadB64));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      if ('${payload['type']}' != 'monthly_subscription') {
        return (ok: false, message: 'Unsupported activation code type.', payload: null);
      }
      return (ok: true, message: 'OK', payload: payload);
    } catch (_) {
      return (ok: false, message: 'Activation code payload is corrupted.', payload: null);
    }
  }

  String _sign(String payloadB64, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return _b64UrlNoPad(hmac.convert(utf8.encode(payloadB64)).bytes);
  }

  String _b64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  List<int> _b64UrlDecodeNoPad(String input) {
    final padLen = (4 - input.length % 4) % 4;
    return base64Url.decode(input + ('=' * padLen));
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class SubscriptionStatus {
  final DateTime activatedAt;
  final DateTime expiresAt;
  final bool expired;
  final int daysLeft;
  final int daysUsed;
  final bool inReminderWindow;
  final bool isActivated;

  const SubscriptionStatus({
    required this.activatedAt,
    required this.expiresAt,
    required this.expired,
    required this.daysLeft,
    required this.daysUsed,
    required this.inReminderWindow,
    required this.isActivated,
  });
}

class ActivationResult {
  final bool ok;
  final String message;
  const ActivationResult({required this.ok, required this.message});
}
