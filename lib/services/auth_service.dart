import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/loan.dart';
import 'mother_data_cache.dart';

class AuthService {
  static const MethodChannel _platformChannel = MethodChannel(
    'child_ui_app/platform',
  );
  static const String _externalBackupDirName = 'ChildUiBackups';
  static const String _externalBackupFileName = 'mother_urls_backup.json';
  static bool _restoreAttempted = false;
  static const String _tokenKey = 'childSessionToken';
  static const String _baseUrlKey = 'motherBaseUrl';
  static const String _baseUrlHistoryKey = 'motherBaseUrlHistory';
  static const String _userTypeKey = 'userType';
  static const String _userTypeRemote = 'REMOTE';
  static const String _nameKey = 'userName';
  static const String _emailKey = 'userEmail';
  static const String _roleKey = 'userRole';
  static const String _profilePicKey = 'userProfilePic';
  static const String _cachedLoginEmailKey = 'cachedLoginEmail';
  static const String _cachedLoginPasswordKey = 'cachedLoginPassword';
  static const String _rememberLoginPasswordKey = 'rememberLoginPassword';
  static const String _mdnsServiceType = '_motherapi._tcp.local';
  static const int _udpDiscoveryPort = 42109;
  static const String _udpDiscoveryToken = 'mother-discovery-v1';
  static Future<void>? _reconnectInProgress;

  Future<void> setBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      return;
    }
    await prefs.setString(_baseUrlKey, normalized);
    await _addBaseUrlToHistory(normalized);
  }

  Future<String> getBaseUrl() async {
    await _tryRestoreHistoryFromExternalBackupIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? 'http://192.168.43.1:8090';
  }

  Future<List<String>> getBaseUrlHistory() async {
    await _tryRestoreHistoryFromExternalBackupIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_baseUrlHistoryKey) ?? <String>[];
    final normalized = raw
        .map(_normalizeBaseUrl)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return _dedupePreserveOrder(normalized);
  }

  Future<void> addBaseUrlToHistory(String baseUrl) async {
    await _addBaseUrlToHistory(baseUrl);
  }

  Future<void> removeBaseUrlFromHistory(String baseUrl) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getBaseUrlHistory();
    final updated = current.where((entry) => entry != normalized).toList();
    await prefs.setStringList(_baseUrlHistoryKey, updated);
    await _requestPlatformBackup();
    await _syncHistoryToExternalBackup(updated);
  }

  Future<void> updateBaseUrlHistoryEntry({
    required String oldBaseUrl,
    required String newBaseUrl,
  }) async {
    final oldNormalized = _normalizeBaseUrl(oldBaseUrl);
    final newNormalized = _normalizeBaseUrl(newBaseUrl);
    if (oldNormalized.isEmpty || newNormalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getBaseUrlHistory();
    final replaced = current
        .map((entry) => entry == oldNormalized ? newNormalized : entry)
        .toList();
    final deduped = _dedupePreserveOrder(replaced);
    await prefs.setStringList(_baseUrlHistoryKey, deduped.take(20).toList());
    await _requestPlatformBackup();
    await _syncHistoryToExternalBackup(deduped);
  }

  Future<void> replaceBaseUrlHistory(List<String> baseUrls) async {
    final prefs = await SharedPreferences.getInstance();
    final deduped = _dedupePreserveOrder(baseUrls).take(20).toList();
    await prefs.setStringList(_baseUrlHistoryKey, deduped);
    if (deduped.isNotEmpty) {
      await prefs.setString(_baseUrlKey, deduped.first);
    }
    await _requestPlatformBackup();
    await _syncHistoryToExternalBackup(deduped);
  }

  Uri _buildUri(String baseUrl, String path) {
    final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .post(
            _buildUri(baseUrl, '/auth/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'email': email, 'password': password, 'name': name}),
          )
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 201) return {'success': true, ...data};
      return {'success': false, ...data};
    } on SocketException {
      return {
        'success': false,
        'message': 'Mother API cannot be reached. Check Wi-Fi/hotspot and IP.',
      };
    } on HttpException {
      return {
        'success': false,
        'message': 'Mother API cannot be reached. Check endpoint URL.',
      };
    } on FormatException {
      return {
        'success': false,
        'message': 'Mother API returned invalid response.',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Mother API request failed.',
      };
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final currentBase = await getBaseUrl();
    final history = await getBaseUrlHistory();
    final candidates = _dedupePreserveOrder(<String>[currentBase, ...history]
        .map(_normalizeBaseUrl)
        .where((value) => value.isNotEmpty)
        .toList(growable: false));

    bool reachedAnyMother = false;
    String? lastFailureMessage;

    for (final baseUrl in candidates) {
      final attempt = await _attemptLoginOnBaseUrl(
        baseUrl: baseUrl,
        email: email,
        password: password,
      );

      if (attempt.success) {
        final data = attempt.data;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, data['token'].toString());
        await prefs.setString(_userTypeKey, _userTypeRemote);
        await cacheLoginCredentials(email: email, password: password);
        await _cacheProfileFromMap(data);
        await setBaseUrl(baseUrl);
        return {'success': true, ...data};
      }

      if (attempt.reachedMotherApi) {
        reachedAnyMother = true;
      }
      if (attempt.message != null && attempt.message!.trim().isNotEmpty) {
        lastFailureMessage = attempt.message!.trim();
      }
    }

    if (!reachedAnyMother) {
      return {
        'success': false,
        'message':
            'The mother IP has not been used previously. Please input new IP from Mother Settings.',
      };
    }

    return {
      'success': false,
      'message': lastFailureMessage ?? 'Login failed. Check mother API connection.',
    };
  }

  Future<_LoginAttemptResult> _attemptLoginOnBaseUrl({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            _buildUri(baseUrl, '/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 8));

      final data = _decodeBody(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        return _LoginAttemptResult(
          success: true,
          reachedMotherApi: true,
          data: data,
        );
      }
      return _LoginAttemptResult(
        success: false,
        reachedMotherApi: true,
        data: data,
        message: (data['message'] ?? 'Login failed').toString(),
      );
    } on SocketException {
      return const _LoginAttemptResult(
        success: false,
        reachedMotherApi: false,
        message: 'Mother API cannot be reached. Check Wi-Fi/hotspot and IP.',
      );
    } on HttpException {
      return const _LoginAttemptResult(
        success: false,
        reachedMotherApi: false,
        message: 'Mother API cannot be reached. Check endpoint URL.',
      );
    } on FormatException {
      return const _LoginAttemptResult(
        success: false,
        reachedMotherApi: false,
        message: 'Mother API returned invalid response.',
      );
    } catch (_) {
      return const _LoginAttemptResult(
        success: false,
        reachedMotherApi: false,
        message: 'Login failed. Check mother API connection.',
      );
    }
  }

  Future<(bool ok, String message)> testConnection() async {
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .get(_buildUri(baseUrl, '/health'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        return (true, 'Connected to mother API.');
      }
      return (false, 'Mother API responded with ${res.statusCode}.');
    } on SocketException {
      return (false, 'Mother API cannot be reached from this phone.');
    } catch (_) {
      return (false, 'Failed to connect to mother API.');
    }
  }

  Future<(bool ok, String message)> testBaseUrlHealth(String baseUrl) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      return (false, 'Invalid base URL.');
    }
    return _testHealthOnBaseUrl(normalized);
  }

  Future<(bool ok, String message, String? workingBaseUrl)>
  testConnectionWithFallback() async {
    final discovered = await _discoverMotherBaseUrlsWithMulticastLock();
    final heuristic = _dedupePreserveOrder(<String>[
      ...discovered,
      ...await _heuristicMotherBaseUrls(),
    ]);
    if (heuristic.isNotEmpty) {
      for (final baseUrl in heuristic) {
        final result = await _testHealthOnBaseUrl(baseUrl);
        if (result.$1) {
          await setBaseUrl(baseUrl);
          final viaDiscovery = discovered.contains(baseUrl);
          return (
            true,
            viaDiscovery
                ? 'Connected to mother API via network discovery at $baseUrl'
                : 'Connected to mother API at $baseUrl',
            baseUrl,
          );
        }
      }
    }

    final currentBase = await getBaseUrl();
    final history = await getBaseUrlHistory();
    final candidates = _dedupePreserveOrder(<String>[currentBase, ...history]
        .map(_normalizeBaseUrl)
        .where((value) => value.isNotEmpty)
        .toList(growable: false));

    if (candidates.isEmpty) {
      return (
        false,
        'No mother base URL found. Please provide a new URL from Mother Settings.',
        null,
      );
    }

    for (final baseUrl in candidates) {
      final result = await _testHealthOnBaseUrl(baseUrl);
      if (result.$1) {
        await setBaseUrl(baseUrl);
        return (true, 'Connected to mother API at $baseUrl', baseUrl);
      }
    }

    return (
      false,
      'Mother discovery failed and no saved mother base URL works. Please provide a new mother base URL from Mother Settings.',
      null,
    );
  }

  Future<List<String>> _discoverMotherBaseUrls() async {
    final discovered = <String>[];
    try {
      discovered.addAll(await _discoverViaMdns());
    } catch (_) {
      // ignore discovery failure
    }
    try {
      discovered.addAll(await _discoverViaUdp());
    } catch (_) {
      // ignore discovery failure
    }
    return _dedupePreserveOrder(discovered);
  }

  Future<List<String>> _discoverMotherBaseUrlsWithMulticastLock() async {
    try {
      await _platformChannel.invokeMethod<void>('acquireMulticastLock');
    } catch (_) {}
    try {
      return await _discoverMotherBaseUrls();
    } finally {
      try {
        await _platformChannel.invokeMethod<void>('releaseMulticastLock');
      } catch (_) {}
    }
  }

  /// Fallback URLs when mDNS/UDP discovery fails (offline Wi‑Fi, hotspot APs).
  Future<List<String>> _heuristicMotherBaseUrls() async {
    const port = 8090;
    const staticGateways = <String>[
      '192.168.43.1',
      '192.168.137.1',
      '192.168.4.1',
      '192.168.49.1',
      '172.20.10.1',
      '192.168.1.1',
      '192.168.0.1',
    ];
    final fromStatic =
        staticGateways.map((g) => 'http://$g:$port').toList(growable: false);
    final fromInterfaces = <String>[];
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) {
            continue;
          }
          final raw = addr.rawAddress;
          if (raw.length != 4) continue;
          fromInterfaces.add(
            'http://${raw[0]}.${raw[1]}.${raw[2]}.1:$port',
          );
        }
      }
    } catch (_) {}
    return _dedupePreserveOrder(<String>[...fromInterfaces, ...fromStatic]);
  }

  Future<List<String>> _discoverViaMdns() async {
    final discovered = <String>[];
    final client = MDnsClient();
    try {
      await client.start();
      await for (final ptr in client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_mdnsServiceType))
          .timeout(const Duration(seconds: 3), onTimeout: (sink) => sink.close())) {
        await for (final srv in client
            .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
            .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          await for (final ip in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
              .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
            discovered.add('http://${ip.address.address}:${srv.port}');
          }
        }
      }
    } catch (_) {
      // no-op
    } finally {
      client.stop();
    }
    return discovered;
  }

  Future<List<String>> _discoverViaUdp() async {
    final discovered = <String>[];
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final payload = utf8.encode(jsonEncode({
        'type': 'discover_mother',
        'token': _udpDiscoveryToken,
      }));

      final completer = Completer<void>();
      final timer = Timer(const Duration(seconds: 4), () {
        if (!completer.isCompleted) completer.complete();
      });

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        try {
          final decoded = jsonDecode(utf8.decode(datagram.data));
          if (decoded is! Map<String, dynamic>) return;
          if ((decoded['token'] ?? '').toString() != _udpDiscoveryToken) return;
          final type = (decoded['type'] ?? '').toString();
          if (type != 'mother_hello') return;

          final baseUrl = (decoded['baseUrl'] ?? '').toString().trim();
          if (baseUrl.isNotEmpty) {
            discovered.add(baseUrl);
            return;
          }

          final ip = (decoded['ip'] ?? datagram.address.address).toString().trim();
          final portRaw = decoded['port'];
          final port = portRaw is int ? portRaw : int.tryParse('$portRaw');
          if (ip.isNotEmpty && port != null && port > 0) {
            discovered.add('http://$ip:$port');
          }
        } catch (_) {
          // ignore invalid response packets
        }
      });

      await _sendUdpDiscoveryProbes(socket, payload);
      await completer.future;
      timer.cancel();
    } catch (_) {
      // no-op
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
    return discovered;
  }

  Future<void> _sendUdpDiscoveryProbes(
    RawDatagramSocket socket,
    List<int> payload,
  ) async {
    final seen = <String>{};
    void sendTo(InternetAddress address) {
      try {
        final key = address.address;
        if (!seen.add(key)) return;
        socket.send(payload, address, _udpDiscoveryPort);
      } catch (_) {}
    }

    sendTo(InternetAddress('255.255.255.255'));

    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) {
            continue;
          }
          final raw = addr.rawAddress;
          if (raw.length != 4) continue;
          sendTo(
            InternetAddress('${raw[0]}.${raw[1]}.${raw[2]}.255'),
          );
        }
      }
    } catch (_) {}
  }

  Future<(bool ok, String message)> _testHealthOnBaseUrl(String baseUrl) async {
    try {
      final res = await http
          .get(_buildUri(baseUrl, '/health'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        return (true, 'Connected to mother API.');
      }
      return (false, 'Mother API responded with ${res.statusCode}.');
    } on SocketException {
      return (false, 'Mother API cannot be reached from this phone.');
    } catch (_) {
      return (false, 'Failed to connect to mother API.');
    }
  }

  String _normalizeBaseUrl(String baseUrl) {
    var normalized = baseUrl.trim();
    if (normalized.isEmpty) return '';
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    return normalized.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _addBaseUrlToHistory(String baseUrl) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_baseUrlHistoryKey) ?? <String>[];
    final merged = _dedupePreserveOrder(<String>[normalized, ...current]);
    await prefs.setStringList(_baseUrlHistoryKey, merged.take(20).toList());
    await _requestPlatformBackup();
    await _syncHistoryToExternalBackup(merged);
  }

  List<String> _dedupePreserveOrder(List<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      final normalized = _normalizeBaseUrl(value);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      out.add(normalized);
    }
    return out;
  }

  Future<void> cacheLoginCredentials({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedLoginEmailKey, email.trim());
    final rememberPassword = prefs.getBool(_rememberLoginPasswordKey) ?? false;
    if (rememberPassword) {
      await prefs.setString(_cachedLoginPasswordKey, password);
    } else {
      await prefs.remove(_cachedLoginPasswordKey);
    }
  }

  Future<Map<String, String>> getCachedLoginCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_cachedLoginEmailKey) ?? '',
      'password': prefs.getString(_cachedLoginPasswordKey) ?? '',
    };
  }

  Future<bool> getRememberLoginPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberLoginPasswordKey) ?? false;
  }

  Future<void> setRememberLoginPassword(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberLoginPasswordKey, remember);
    if (!remember) {
      await prefs.remove(_cachedLoginPasswordKey);
    }
  }

  Future<void> _requestPlatformBackup() async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod<void>('requestBackupNow');
    } catch (_) {
      // Ignore platform backup failures; local persistence still works.
    }
  }

  Future<void> _tryRestoreHistoryFromExternalBackupIfNeeded() async {
    if (_restoreAttempted || !Platform.isAndroid) return;
    _restoreAttempted = true;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_baseUrlHistoryKey) ?? <String>[];
    if (existing.isNotEmpty) return;

    final backupFile = await _getExternalBackupFile(createIfMissing: false);
    if (backupFile == null || !await backupFile.exists()) return;
    try {
      final content = await backupFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return;
      final raw = decoded['baseUrls'];
      if (raw is! List) return;
      final urls = raw
          .map((entry) => _normalizeBaseUrl(entry.toString()))
          .where((entry) => entry.isNotEmpty)
          .toList();
      if (urls.isEmpty) return;
      final deduped = _dedupePreserveOrder(urls).take(20).toList();
      await prefs.setStringList(_baseUrlHistoryKey, deduped);
      await prefs.setString(_baseUrlKey, deduped.first);
    } catch (_) {
      // Ignore invalid backup file content.
    }
  }

  Future<void> _syncHistoryToExternalBackup(List<String> urls) async {
    if (!Platform.isAndroid) return;
    try {
      final backupFile = await _getExternalBackupFile(createIfMissing: true);
      if (backupFile == null) return;
      final payload = <String, dynamic>{
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'baseUrls': _dedupePreserveOrder(urls).take(20).toList(),
      };
      await backupFile.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Ignore external backup write failures.
    }
  }

  Future<Map<String, dynamic>> getExternalBackupStatus() async {
    const path = '/storage/emulated/0/$_externalBackupDirName/$_externalBackupFileName';
    if (!Platform.isAndroid) {
      return {
        'supported': false,
        'path': path,
        'permissionGranted': false,
        'fileExists': false,
        'readable': false,
        'writable': false,
        'message': 'External backup file status is only supported on Android.',
      };
    }

    final permissionGranted = await _hasExternalStoragePermission();
    final file = await _getExternalBackupFile(
      createIfMissing: false,
      requestPermission: false,
    );
    final exists = file != null && await file.exists();
    bool readable = false;
    bool writable = false;

    if (exists) {
      try {
        await file.readAsString();
        readable = true;
      } catch (_) {
        readable = false;
      }
    }

    if (permissionGranted) {
      try {
        final writableFile = await _getExternalBackupFile(createIfMissing: true);
        if (writableFile != null) {
          if (!await writableFile.exists()) {
            await writableFile.create(recursive: true);
          }
          writable = await writableFile.parent.exists();
        }
      } catch (_) {
        writable = false;
      }
    }

    String message;
    if (!permissionGranted) {
      message = 'Permission required to access shared backup file.';
    } else if (!exists) {
      message = 'Backup file not found yet. It will be created after URL save.';
    } else if (readable && writable) {
      message = 'Backup file is accessible for restore and update.';
    } else if (readable) {
      message = 'Backup file is readable but not writable.';
    } else {
      message = 'Backup file exists but cannot be read.';
    }

    return {
      'supported': true,
      'path': path,
      'permissionGranted': permissionGranted,
      'fileExists': exists,
      'readable': readable,
      'writable': writable,
      'message': message,
    };
  }

  Future<File?> _getExternalBackupFile({
    required bool createIfMissing,
    bool requestPermission = true,
  }) async {
    final granted = requestPermission
        ? await _ensureExternalStoragePermission()
        : await _hasExternalStoragePermission();
    if (!granted) return null;

    final directory = Directory('/storage/emulated/0/$_externalBackupDirName');
    if (createIfMissing && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    if (!await directory.exists()) return null;
    return File('${directory.path}/$_externalBackupFileName');
  }

  Future<bool> _ensureExternalStoragePermission() async {
    if (!Platform.isAndroid) return false;

    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;
    final requestedManage = await Permission.manageExternalStorage.request();
    if (requestedManage.isGranted) return true;

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;
    final requestedStorage = await Permission.storage.request();
    return requestedStorage.isGranted;
  }

  Future<bool> _hasExternalStoragePermission() async {
    if (!Platform.isAndroid) return false;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;
    final storage = await Permission.storage.status;
    return storage.isGranted;
  }

  Future<bool> _tryAutoReconnectMother() async {
    if (_reconnectInProgress != null) {
      await _reconnectInProgress;
      final test = await testConnection();
      return test.$1;
    }

    final completer = Completer<void>();
    _reconnectInProgress = completer.future;
    try {
      // Keep trying until mother comes back online.
      // This guarantees page refresh/API retries can recover automatically.
      while (true) {
        try {
          final result = await testConnectionWithFallback();
          if (result.$1) break;
        } catch (_) {
          // Ignore and keep retrying.
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (_) {
      // best effort reconnect only
    } finally {
      completer.complete();
      _reconnectInProgress = null;
    }

    final test = await testConnection();
    return test.$1;
  }

  bool _shouldReconnectForStatus(int statusCode) {
    return statusCode == 502 || statusCode == 503 || statusCode == 504;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    MotherDataCache.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userTypeKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_profilePicKey);
  }

  Future<String> getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final value = (prefs.getString(_userTypeKey) ?? _userTypeRemote)
        .trim()
        .toUpperCase();
    return value.isEmpty ? _userTypeRemote : value;
  }

  Future<bool> isRemoteUser() async => (await getUserType()) == _userTypeRemote;

  Future<Map<String, dynamic>> getRemoteAuthorized({
    required String path,
    bool allowReconnectRetry = true,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': 'Missing session token'};
    }
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .get(
            _buildUri(baseUrl, path),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': true, ...data};
      }
      if (allowReconnectRetry && _shouldReconnectForStatus(res.statusCode)) {
        if (await _tryAutoReconnectMother()) {
          return getRemoteAuthorized(path: path, allowReconnectRetry: false);
        }
      }
      return {
        'success': false,
        'message': (data['message'] ?? 'Request failed (${res.statusCode})')
            .toString(),
        ...data,
      };
    } on SocketException {
      if (await _tryAutoReconnectMother()) {
        return getRemoteAuthorized(path: path, allowReconnectRetry: false);
      }
      return {
        'success': false,
        'message': 'Mother API cannot be reached. Check connection.',
      };
    } catch (_) {
      return {'success': false, 'message': 'Remote request failed.'};
    }
  }

  Future<Map<String, dynamic>> postRemoteAuthorized({
    required String path,
    required Map<String, dynamic> body,
    bool allowReconnectRetry = true,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': 'Missing session token'};
    }
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .post(
            _buildUri(baseUrl, path),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': true, ...data};
      }
      if (allowReconnectRetry && _shouldReconnectForStatus(res.statusCode)) {
        if (await _tryAutoReconnectMother()) {
          return postRemoteAuthorized(
            path: path,
            body: body,
            allowReconnectRetry: false,
          );
        }
      }
      return {
        'success': false,
        'message': (data['message'] ?? 'Request failed (${res.statusCode})')
            .toString(),
        ...data,
      };
    } on SocketException {
      if (await _tryAutoReconnectMother()) {
        return postRemoteAuthorized(
          path: path,
          body: body,
          allowReconnectRetry: false,
        );
      }
      return {
        'success': false,
        'message': 'Mother API cannot be reached. Check connection.',
      };
    } catch (_) {
      return {'success': false, 'message': 'Remote request failed.'};
    }
  }

  Future<Map<String, dynamic>> putRemoteAuthorized({
    required String path,
    required Map<String, dynamic> body,
    bool allowReconnectRetry = true,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': 'Missing session token'};
    }
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .put(
            _buildUri(baseUrl, path),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': true, ...data};
      }
      if (allowReconnectRetry && _shouldReconnectForStatus(res.statusCode)) {
        if (await _tryAutoReconnectMother()) {
          return putRemoteAuthorized(
            path: path,
            body: body,
            allowReconnectRetry: false,
          );
        }
      }
      return {
        'success': false,
        'message': (data['message'] ?? 'Request failed (${res.statusCode})')
            .toString(),
        ...data,
      };
    } on SocketException {
      if (await _tryAutoReconnectMother()) {
        return putRemoteAuthorized(
          path: path,
          body: body,
          allowReconnectRetry: false,
        );
      }
      return {
        'success': false,
        'message': 'Mother API cannot be reached. Check connection.',
      };
    } catch (_) {
      return {'success': false, 'message': 'Remote request failed.'};
    }
  }

  Future<Map<String, dynamic>> deleteRemoteAuthorized({
    required String path,
    bool allowReconnectRetry = true,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': 'Missing session token'};
    }
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .delete(
            _buildUri(baseUrl, path),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': true, ...data};
      }
      if (allowReconnectRetry && _shouldReconnectForStatus(res.statusCode)) {
        if (await _tryAutoReconnectMother()) {
          return deleteRemoteAuthorized(path: path, allowReconnectRetry: false);
        }
      }
      return {
        'success': false,
        'message': (data['message'] ?? 'Request failed (${res.statusCode})')
            .toString(),
        ...data,
      };
    } on SocketException {
      if (await _tryAutoReconnectMother()) {
        return deleteRemoteAuthorized(path: path, allowReconnectRetry: false);
      }
      return {
        'success': false,
        'message': 'Mother API cannot be reached. Check connection.',
      };
    } catch (_) {
      return {'success': false, 'message': 'Remote request failed.'};
    }
  }

  bool _hasRecordId(Map<String, dynamic> payload) {
    final id = payload['id'];
    if (id == null) return false;
    if (id is num) return id > 0;
    final parsed = int.tryParse(id.toString());
    return (parsed ?? 0) > 0;
  }

  Future<Map<String, dynamic>> saveRemoteStore(Map<String, dynamic> payload) {
    if (_hasRecordId(payload)) {
      return putRemoteAuthorized(path: '/stores', body: payload);
    }
    return postRemoteAuthorized(path: '/stores', body: payload);
  }

  Future<Map<String, dynamic>> saveRemoteClient(Map<String, dynamic> payload) {
    if (_hasRecordId(payload)) {
      return putRemoteAuthorized(path: '/clients', body: payload);
    }
    return postRemoteAuthorized(path: '/clients', body: payload);
  }

  Future<Map<String, dynamic>> saveRemoteItem(Map<String, dynamic> payload) {
    if (_hasRecordId(payload)) {
      return putRemoteAuthorized(path: '/items', body: payload);
    }
    return postRemoteAuthorized(path: '/items', body: payload);
  }

  Future<Map<String, dynamic>> saveRemoteUnit(Map<String, dynamic> payload) {
    if (_hasRecordId(payload)) {
      return putRemoteAuthorized(path: '/units', body: payload);
    }
    return postRemoteAuthorized(path: '/units', body: payload);
  }

  Future<Map<String, dynamic>> fetchRemoteUnits() {
    return getRemoteAuthorized(path: '/units');
  }

  Future<List<String>> fetchRemoteItemCategories({required String type}) async {
    final normalized = type.trim().toLowerCase();
    if (normalized != 'sale' && normalized != 'business') {
      return const <String>[];
    }
    final res = await getRemoteAuthorized(
      path: '/item-categories?type=$normalized',
    );
    if (res['success'] != true) return const <String>[];
    final rows = res['data'];
    if (rows is! List) return const <String>[];
    return rows
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<Map<String, dynamic>> saveRemoteItemCategory({
    required String type,
    required String name,
    String? oldName,
  }) {
    final normalized = type.trim().toLowerCase();
    return postRemoteAuthorized(
      path: '/item-categories?type=$normalized',
      body: <String, dynamic>{
        'name': name.trim(),
        'oldName': (oldName ?? '').trim(),
      },
    );
  }

  Future<Map<String, dynamic>> deleteRemoteItemCategory({
    required String type,
    required String name,
  }) {
    final normalized = type.trim().toLowerCase();
    return postRemoteAuthorized(
      path: '/item-categories/delete',
      body: <String, dynamic>{
        'type': normalized,
        'name': name.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> fetchRemoteServices() {
    return getRemoteAuthorized(path: '/services');
  }

  Future<Map<String, dynamic>> fetchRemoteServiceById(int serviceId) {
    if (serviceId <= 0) {
      return Future.value({
        'success': false,
        'message': 'Invalid service id.',
      });
    }
    return getRemoteAuthorized(path: '/services/$serviceId');
  }

  Future<Map<String, dynamic>> saveRemoteService(Map<String, dynamic> payload) {
    if (_hasRecordId(payload)) {
      return putRemoteAuthorized(path: '/services', body: payload);
    }
    return postRemoteAuthorized(path: '/services', body: payload);
  }

  Future<Map<String, dynamic>> deleteRemoteService(int serviceId) {
    if (serviceId <= 0) {
      return Future.value({
        'success': false,
        'message': 'Invalid service id.',
      });
    }
    return deleteRemoteAuthorized(path: '/services/$serviceId');
  }

  Future<Map<String, dynamic>> deleteRemoteUnit(int unitId) {
    return deleteRemoteAuthorized(path: '/units/$unitId');
  }

  Future<Map<String, dynamic>> receiveRemoteStock(Map<String, dynamic> payload) {
    final normalized = <String, dynamic>{};
    final rawItemId = payload['itemId'] ?? payload['item_id'];
    final rawQty = payload['quantity'];
    final itemId = _asInt(rawItemId);
    final quantity = _asDouble(rawQty);
    if (itemId == null || quantity == null || quantity <= 0) {
      return Future.value(
        {
          'success': false,
          'message': 'Invalid stock payload: itemId and quantity are required.',
        },
      );
    }

    normalized['itemId'] = itemId;
    normalized['quantity'] = quantity;

    final unitCost = _asDouble(payload['unitCost'] ?? payload['unit_cost']);
    if (unitCost != null) {
      normalized['unitCost'] = unitCost;
    }
    final totalCost = _asDouble(payload['totalCost'] ?? payload['total_cost']);
    if (totalCost != null) {
      normalized['totalCost'] = totalCost;
    }
    final sellingPrice =
        _asDouble(payload['sellingPrice'] ?? payload['selling_price']);
    if (sellingPrice != null) {
      normalized['sellingPrice'] = sellingPrice;
    }

    final brand = payload['brand']?.toString().trim();
    if (brand != null && brand.isNotEmpty) {
      normalized['brand'] = brand;
    }

    final expiryDate =
        (payload['expiryDate'] ?? payload['expiry_date'])?.toString().trim();
    if (expiryDate != null && expiryDate.isNotEmpty) {
      normalized['expiryDate'] = expiryDate;
    }

    final storeId = _asInt(payload['storeId'] ?? payload['store_id']);
    if (storeId != null) {
      normalized['storeId'] = storeId;
    }

    return postRemoteAuthorized(path: '/stock/receive', body: normalized);
  }

  Future<Map<String, dynamic>> adjustRemoteStock(Map<String, dynamic> payload) {
    final normalized = <String, dynamic>{};
    final itemId = _asInt(payload['itemId'] ?? payload['item_id']);
    final quantity = _asDouble(payload['quantity']);
    final type = (payload['type'] ?? '').toString().trim().toLowerCase();
    if (itemId == null ||
        quantity == null ||
        quantity <= 0 ||
        (type != 'add' && type != 'remove')) {
      return Future.value(
        {
          'success': false,
          'message': 'Invalid stock adjustment payload.',
        },
      );
    }
    normalized['itemId'] = itemId;
    normalized['quantity'] = quantity;
    normalized['type'] = type;
    final reason = (payload['reason'] ?? '').toString().trim();
    if (reason.isNotEmpty) {
      normalized['reason'] = reason;
    }
    final storeId = _asInt(payload['storeId'] ?? payload['store_id']);
    if (storeId != null) {
      normalized['storeId'] = storeId;
    }
    return postRemoteAuthorized(path: '/stock/adjust', body: normalized);
  }

  Future<Map<String, dynamic>> saveRemoteStockTransfer(
    Map<String, dynamic> payload, {
    bool usePut = false,
  }) {
    final normalized = <String, dynamic>{};
    final fromItemId = _asInt(payload['fromItemId'] ?? payload['from_item_id']);
    final toItemId = _asInt(payload['toItemId'] ?? payload['to_item_id']);
    final fromQuantity =
        _asDouble(payload['fromQuantity'] ?? payload['from_quantity']);
    final conversionFactor = _asDouble(
      payload['conversionFactor'] ?? payload['conversion_factor'],
    );

    if (fromItemId == null ||
        toItemId == null ||
        fromQuantity == null ||
        conversionFactor == null ||
        fromQuantity <= 0 ||
        conversionFactor <= 0) {
      return Future.value(
        {
          'success': false,
          'message':
              'Invalid transfer payload: fromItemId, toItemId, fromQuantity, conversionFactor are required.',
        },
      );
    }

    normalized['fromItemId'] = fromItemId;
    normalized['toItemId'] = toItemId;
    normalized['fromQuantity'] = fromQuantity;
    normalized['conversionFactor'] = conversionFactor;

    final toCostPrice =
        _asDouble(payload['toCostPrice'] ?? payload['to_cost_price']);
    if (toCostPrice != null) {
      normalized['toCostPrice'] = toCostPrice;
    }
    final fromCostPrice =
        _asDouble(payload['fromCostPrice'] ?? payload['from_cost_price']);
    if (fromCostPrice != null) {
      normalized['fromCostPrice'] = fromCostPrice;
    }
    final toSellingPrice =
        _asDouble(payload['toSellingPrice'] ?? payload['to_selling_price']);
    if (toSellingPrice != null) {
      normalized['toSellingPrice'] = toSellingPrice;
    }
    final storeId = _asInt(payload['storeId'] ?? payload['store_id']);
    if (storeId != null) {
      normalized['storeId'] = storeId;
    }
    final notes = payload['notes']?.toString().trim();
    if (notes != null && notes.isNotEmpty) {
      normalized['notes'] = notes;
    }

    if (usePut) {
      return putRemoteAuthorized(path: '/stock/transfers', body: normalized);
    }
    return postRemoteAuthorized(path: '/stock/transfers', body: normalized);
  }

  Future<Map<String, dynamic>> createRemoteSale(Map<String, dynamic> payload) {
    return postRemoteAuthorized(path: '/sales', body: payload);
  }

  Future<Map<String, dynamic>> saveRemoteExpense(Map<String, dynamic> payload) {
    if (_hasRecordId(payload)) {
      return putRemoteAuthorized(path: '/expenses', body: payload);
    }
    return postRemoteAuthorized(path: '/expenses', body: payload);
  }

  Future<Map<String, dynamic>> deleteRemoteItem(int itemId) {
    return postRemoteAuthorized(path: '/items/delete', body: {'id': itemId});
  }

  Future<Map<String, dynamic>> deleteRemoteExpense(int expenseId) {
    return postRemoteAuthorized(
      path: '/expenses/delete',
      body: {'id': expenseId},
    );
  }

  Future<Map<String, dynamic>> fetchRemoteDashboardAnalytics({
    String range = 'today',
  }) {
    final normalized = range.trim().toLowerCase();
    return getRemoteAuthorized(path: '/dashboard/analytics?range=$normalized');
  }

  Future<Map<String, dynamic>> fetchRemoteItemTransactions({
    required int itemId,
  }) {
    if (itemId <= 0) {
      return Future.value(
        {
          'success': false,
          'message': 'Invalid itemId for item transactions.',
        },
      );
    }
    return getRemoteAuthorized(path: '/items/transactions?itemId=$itemId');
  }

  Future<Map<String, dynamic>> payRemoteDebt({
    required String customerName,
    required double amount,
    int? clientId,
    bool useClientAccount = false,
  }) {
    return postRemoteAuthorized(
      path: '/debts/pay',
      body: {
        'customerName': customerName.trim(),
        'amount': amount,
        if (clientId != null) 'clientId': clientId,
        'useClientAccount': useClientAccount,
      },
    );
  }

  Future<double?> fetchRemoteClientAccountBalance(int clientId) async {
    final res = await getRemoteAuthorized(
      path: '/clients/account?clientId=$clientId',
    );
    if (res['success'] != true) return null;
    return (res['balance'] as num?)?.toDouble();
  }

  Future<Map<String, dynamic>> postRemoteClientAccountTransaction({
    required int clientId,
    required double amount,
    required String transactionType,
    String? note,
  }) {
    return postRemoteAuthorized(
      path: '/clients/account/transaction',
      body: {
        'clientId': clientId,
        'amount': amount,
        'transactionType': transactionType.trim(),
        'note': (note ?? '').trim(),
      },
    );
  }

  Future<List<Map<String, Object?>>> fetchRemoteClientAccountTransactions(
    int clientId,
  ) async {
    final res = await getRemoteAuthorized(
      path: '/clients/account/transactions?clientId=$clientId',
    );
    if (res['success'] != true) return const [];
    final rows = res['data'];
    if (rows is! List) return const [];
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        out.add(Map<String, Object?>.from(row));
      } else if (row is Map) {
        out.add(Map<String, Object?>.from(row));
      }
    }
    return out;
  }

  Future<List<Loan>> fetchRemoteLoans() async {
    final res = await getRemoteAuthorized(path: '/loans');
    if (res['success'] != true) return const [];
    final rows = res['data'];
    if (rows is! List) return const [];
    final out = <Loan>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        out.add(Loan.fromMap(row));
      } else if (row is Map) {
        out.add(Loan.fromMap(Map<String, dynamic>.from(row)));
      }
    }
    return out;
  }

  Future<List<Map<String, Object?>>> fetchRemoteLoanPayments({
    int? loanId,
    int? clientId,
  }) async {
    final params = <String>[];
    if (loanId != null) params.add('loanId=$loanId');
    if (clientId != null) params.add('clientId=$clientId');
    final suffix = params.isEmpty ? '' : '?${params.join('&')}';
    final res = await getRemoteAuthorized(path: '/loans/payments$suffix');
    if (res['success'] != true) return const [];
    final rows = res['data'];
    if (rows is! List) return const [];
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        out.add(Map<String, Object?>.from(row));
      } else if (row is Map) {
        out.add(Map<String, Object?>.from(row));
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> postRemoteLoanPayment({
    required int loanId,
    required int clientId,
    required double amount,
    int? storeId,
    String? note,
  }) {
    return postRemoteAuthorized(
      path: '/loans/payments',
      body: {
        'loanId': loanId,
        'clientId': clientId,
        'amount': amount,
        if (storeId != null) 'storeId': storeId,
        'note': (note ?? '').trim(),
      },
    );
  }

  Map<String, dynamic> _decodeBody(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<void> _cacheProfile({
    String? name,
    String? email,
    String? role,
    String? profilePic,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) {
      await prefs.setString(_nameKey, name.trim());
    }
    if (email != null) {
      await prefs.setString(_emailKey, email.trim());
    }
    if (role != null) {
      await prefs.setString(_roleKey, role.trim().toUpperCase());
    }
    if (profilePic != null) {
      await prefs.setString(_profilePicKey, profilePic.trim());
    }
  }

  Future<void> _cacheProfileFromMap(Map<String, dynamic> map) async {
    await _cacheProfile(
      name: map['name']?.toString(),
      email: map['email']?.toString(),
      role: map['role']?.toString(),
      profilePic: map['profilePic']?.toString(),
    );
  }

  // Legacy compatibility for old screens still present in project.
  Future<bool> hasAnyAccount() async => true;
  Future<String?> getUsername() async {
    final profile = await getCurrentProfile();
    return profile['name']?.toString();
  }

  Future<String?> getUserRole() async {
    final profile = await getCurrentProfile();
    return profile['role']?.toString();
  }

  Future<Map<String, dynamic>?> getUserDetails() async {
    final profile = await getCurrentProfile();
    return profile;
  }

  Future<Map<String, dynamic>> getCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = <String, dynamic>{
      'name': prefs.getString(_nameKey) ?? '',
      'email': prefs.getString(_emailKey) ?? '',
      'role': prefs.getString(_roleKey) ?? 'ADMIN',
      'profilePic': prefs.getString(_profilePicKey) ?? '',
      'userType': await getUserType(),
    };

    if (!await isRemoteUser()) {
      return cached;
    }

    final remote = await getRemoteAuthorized(path: '/auth/me');
    if (remote['success'] != true) {
      return cached;
    }

    final data = remote['data'];
    final profile = <String, dynamic>{
      'name': data is Map ? (data['name'] ?? cached['name']) : cached['name'],
      'email': data is Map ? (data['email'] ?? cached['email']) : cached['email'],
      'role': data is Map ? (data['role'] ?? cached['role']) : cached['role'],
      'profilePic':
          data is Map ? (data['profilePic'] ?? cached['profilePic']) : cached['profilePic'],
      'userType': await getUserType(),
    };
    await _cacheProfileFromMap(profile);
    return profile;
  }

  Future<(bool ok, String message)> updateProfile({
    required String name,
    required String email,
    String? newPassword,
    String? profilePic,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'profilePic': (profilePic ?? '').trim(),
    };
    final password = (newPassword ?? '').trim();
    if (password.isNotEmpty) {
      payload['newPassword'] = password;
    }

    if (!await isRemoteUser()) {
      await _cacheProfile(
        name: name,
        email: email,
        profilePic: profilePic,
      );
      return (true, 'Profile updated locally.');
    }

    final remote = await postRemoteAuthorized(path: '/auth/profile', body: payload);
    if (remote['success'] == true) {
      final data = remote['data'];
      if (data is Map<String, dynamic>) {
        await _cacheProfileFromMap(data);
      } else {
        await _cacheProfile(
          name: name,
          email: email,
          profilePic: profilePic,
        );
      }
      return (true, (remote['message'] ?? 'Profile updated.').toString());
    }
    return (false, (remote['message'] ?? 'Failed to update profile.').toString());
  }
}

class _LoginAttemptResult {
  const _LoginAttemptResult({
    required this.success,
    required this.reachedMotherApi,
    this.data = const <String, dynamic>{},
    this.message,
  });

  final bool success;
  final bool reachedMotherApi;
  final Map<String, dynamic> data;
  final String? message;
}
