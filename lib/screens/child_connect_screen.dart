import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../navigation/app_router.dart';
import '../services/auth_service.dart';
import 'use_new_url_screen.dart';

class ChildConnectScreen extends StatefulWidget {
  const ChildConnectScreen({super.key});

  @override
  State<ChildConnectScreen> createState() => _ChildConnectScreenState();
}

class _ChildConnectScreenState extends State<ChildConnectScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _auth = AuthService();
  static const MethodChannel _platformChannel = MethodChannel(
    'child_ui_app/platform',
  );
  bool _testing = false;
  bool _autoChecking = false;
  bool _flowInProgress = false;
  bool _waitingForWifiChange = false;
  List<String> _previousIps = const [];
  String _status = '';
  int _discoveryFailures = 0;
  List<_UrlTestResult> _testResults = const [];
  Map<String, dynamic>? _backupStatus;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startBackgroundReconnectChecks();
  }

  Future<void> _load() async {
    _controller.text = await _auth.getBaseUrl();
    _previousIps = await _auth.getBaseUrlHistory();
    _backupStatus = await _auth.getExternalBackupStatus();
    _autoChecking = true;
    if (mounted) setState(() {});
    await _runConnectionFlow(autoRedirectToLogin: true);
    _backupStatus = await _auth.getExternalBackupStatus();
    if (!mounted) return;
    setState(() => _autoChecking = false);
  }

  Future<void> _save() async {
    await _auth.setBaseUrl(_controller.text.trim());
    _previousIps = await _auth.getBaseUrlHistory();
    _backupStatus = await _auth.getExternalBackupStatus();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mother endpoint saved')));
  }

  Future<void> _openUseNewUrlPage() async {
    final entered = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const UseNewUrlScreen(),
      ),
    );
    if (!mounted || entered == null) return;
    _controller.text = await _auth.getBaseUrl();
    _previousIps = await _auth.getBaseUrlHistory();
    _backupStatus = await _auth.getExternalBackupStatus();
    setState(() {
      _status = 'New URL saved. Testing connection...';
    });
    await _runConnectionFlow(autoRedirectToLogin: true);
  }

  Future<void> _addCurrentUrlToSavedList() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a mother base URL first.')),
      );
      return;
    }
    await _auth.addBaseUrlToHistory(text);
    _previousIps = await _auth.getBaseUrlHistory();
    _backupStatus = await _auth.getExternalBackupStatus();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('URL added to saved list')));
  }

  Future<void> _deleteSavedUrl(String url) async {
    await _auth.removeBaseUrlFromHistory(url);
    _previousIps = await _auth.getBaseUrlHistory();
    _backupStatus = await _auth.getExternalBackupStatus();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('URL removed from saved list')));
  }

  Future<void> _exportSavedUrlsBackup() async {
    final urls = await _auth.getBaseUrlHistory();
    if (urls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved URLs to export yet.')),
      );
      return;
    }

    final payload = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'baseUrls': urls,
    };
    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}${Platform.pathSeparator}mother_urls_backup.json';
    final file = File(filePath);
    await file.writeAsString(jsonString, flush: true);

    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Mother URL backup for child app',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup file ready. Save it to Drive/Files from share sheet.'),
      ),
    );
  }

  Future<void> _importSavedUrlsBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;

    String? content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null || content.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected backup file is empty.')),
      );
      return;
    }

    try {
      final decoded = jsonDecode(content);
      final urlsRaw =
          decoded is Map<String, dynamic> ? decoded['baseUrls'] : null;
      if (urlsRaw is! List) {
        throw const FormatException('Invalid backup format');
      }
      final urls = urlsRaw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList();

      if (urls.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup has no URLs to import.')),
        );
        return;
      }

      await _auth.replaceBaseUrlHistory(urls);
      _previousIps = await _auth.getBaseUrlHistory();
      _controller.text = await _auth.getBaseUrl();
      _backupStatus = await _auth.getExternalBackupStatus();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${_previousIps.length} saved URL(s).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid backup file. Import failed.')),
      );
    }
  }

  Future<void> _editSavedUrl(String oldUrl) async {
    final controller = TextEditingController(text: oldUrl);
    final newValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit saved URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Mother Base URL',
            hintText: 'http://192.168.x.x:8090',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newValue == null || newValue.trim().isEmpty) return;
    await _auth.updateBaseUrlHistoryEntry(oldBaseUrl: oldUrl, newBaseUrl: newValue);
    _previousIps = await _auth.getBaseUrlHistory();
    _backupStatus = await _auth.getExternalBackupStatus();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved URL updated')));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForWifiChange) {
      _waitingForWifiChange = false;
      _runConnectionFlow(autoRedirectToLogin: true, silent: false);
    }
  }

  void _startBackgroundReconnectChecks() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (!mounted || _flowInProgress || _testing || _autoChecking) return;
      await _runConnectionFlow(autoRedirectToLogin: true, silent: true);
    });
  }

  Future<bool> _checkWifiConnection({bool silent = false}) async {
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.wifi) ||
        connectivityResults.contains(ConnectivityResult.ethernet)) {
      return true;
    }
    // Offline LAN / "Connected, no internet" sometimes omits Wi‑Fi from the plugin result.
    if (await _hasPrivateIpv4LanAddress()) return true;
    if (!mounted) return false;
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect this child phone to the mother hotspot or same Wi-Fi first, and ensure mother hotspot is ON.',
          ),
        ),
      );
    }
    return false;
  }

  Future<bool> _hasPrivateIpv4LanAddress() async {
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) {
            continue;
          }
          final raw = addr.rawAddress;
          if (raw.length != 4) continue;
          final a = raw[0];
          final b = raw[1];
          if (a == 10) return true;
          if (a == 172 && b >= 16 && b <= 31) return true;
          if (a == 192 && b == 168) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _openWifiSettings() async {
    _waitingForWifiChange = true;
    try {
      await _platformChannel.invokeMethod<void>('openWifiSettings');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open Wi-Fi settings.')),
      );
    }
  }

  Future<void> _runConnectionFlow({
    required bool autoRedirectToLogin,
    bool silent = false,
  }) async {
    if (_flowInProgress) return;
    _flowInProgress = true;
    try {
      if (!await _checkWifiConnection(silent: silent)) {
        if (!mounted) return;
        setState(() {
          _status = 'Waiting for Wi-Fi connection to mother network.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _status = 'Testing connection to mother using saved URLs...';
      });

      final currentInput = _controller.text.trim();
      if (currentInput.isNotEmpty) {
        await _auth.setBaseUrl(currentInput);
      }

      final result = await _auth.testConnectionWithFallback();
      _previousIps = await _auth.getBaseUrlHistory();
      _controller.text = await _auth.getBaseUrl();
      _backupStatus = await _auth.getExternalBackupStatus();
      if (!mounted) return;

      if (result.$1) {
        _discoveryFailures = 0;
      } else {
        _discoveryFailures += 1;
      }
      setState(() {
        _status = result.$2;
      });
      if (!silent || result.$1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.$2),
            backgroundColor: result.$1 ? Colors.green : null,
          ),
        );
      }

      if (result.$1 && autoRedirectToLogin) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRouter.login,
          (route) => false,
        );
        return;
      }
      if (!result.$1 && !silent && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connection to Mother failed'),
            content: const Text(
              'Follow these instructions for connection:\n'
              '1) Make sure this child phone is connected to the same Wi-Fi with the mother phone.\n'
              '2) Or connect this child phone to a Wi-Fi/hotspot created by the mother phone.\n'
              '3) Close and reopen the app.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      _flowInProgress = false;
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    await _runConnectionFlow(autoRedirectToLogin: true);
    if (!mounted) return;
    setState(() => _testing = false);
  }

  Future<void> _testAllSavedUrls() async {
    if (!await _checkWifiConnection()) {
      setState(() {
        _status = 'Cannot test saved URLs without Wi-Fi connection.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _status = 'Testing all saved URLs...';
      _testResults = const [];
    });

    final current = await _auth.getBaseUrl();
    final history = await _auth.getBaseUrlHistory();
    final candidates = <String>[current, ...history];
    final unique = <String>[];
    for (final url in candidates) {
      if (!unique.contains(url)) unique.add(url);
    }

    final results = <_UrlTestResult>[];
    for (final url in unique) {
      final test = await _auth.testBaseUrlHealth(url);
      results.add(
        _UrlTestResult(
          url: url,
          ok: test.$1,
          message: test.$2,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResults = results;
      _status = 'Finished testing ${results.length} saved URL(s).';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Mother')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Mother Base URL',
                hintText: 'http://192.168.x.x:8090',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Current value: ${_controller.text.trim()}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save Connection'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openUseNewUrlPage,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.link),
                label: const Text('Use New URL'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: (_testing || _autoChecking) ? null : _testConnection,
                child: Text(_testing ? 'Testing...' : 'Test Connection'),
              )
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    (_testing || _autoChecking) ? null : _addCurrentUrlToSavedList,
                icon: const Icon(Icons.add),
                label: const Text('Add URL to Saved List'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_testing || _autoChecking) ? null : _testAllSavedUrls,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Test All Saved URLs'),
              ),
            ),
            const SizedBox(height: 8),
            if (_discoveryFailures > 0) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _discoveryFailures == 1
                      ? 'Mother may be on another Wi-Fi network.'
                      : 'Mother still not discovered after $_discoveryFailures checks.',
                  style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_testing || _autoChecking) ? null : _openWifiSettings,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Change Wi-Fi Network'),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'After changing Wi-Fi, return to app and discovery will run again automatically.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_testing || _autoChecking)
                        ? null
                        : _exportSavedUrlsBackup,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Export URLs'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_testing || _autoChecking)
                        ? null
                        : _importSavedUrlsBackup,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Import URLs'),
                  ),
                ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _BackupStatusCard(status: _backupStatus),
            if (_testResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 130,
                child: ListView.separated(
                  itemCount: _testResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _testResults[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        result.ok ? Icons.check_circle : Icons.cancel,
                        color: result.ok ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      title: Text(
                        result.url,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        result.message,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Previously connected base URLs',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            if (_previousIps.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No previously connected URLs yet.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: ListView.separated(
                  itemCount: _previousIps.length,
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final ip = _previousIps[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(ip, style: const TextStyle(fontSize: 13)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Use',
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: () => setState(() => _controller.text = ip),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _editSavedUrl(ip),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _deleteSavedUrl(ip),
                          ),
                        ],
                      ),
                      onTap: () => setState(() => _controller.text = ip),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlTestResult {
  const _UrlTestResult({
    required this.url,
    required this.ok,
    required this.message,
  });

  final String url;
  final bool ok;
  final String message;
}

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({required this.status});

  final Map<String, dynamic>? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return const SizedBox.shrink();
    }

    final supported = status!['supported'] == true;
    final permissionGranted = status!['permissionGranted'] == true;
    final fileExists = status!['fileExists'] == true;
    final readable = status!['readable'] == true;
    final writable = status!['writable'] == true;
    final path = (status!['path'] ?? '').toString();
    final message = (status!['message'] ?? '').toString();

    final ok = supported && permissionGranted && fileExists && readable && writable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ok ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shared backup status',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Path: $path',
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            'Permission: ${permissionGranted ? "granted" : "missing"} | '
            'Exists: ${fileExists ? "yes" : "no"} | '
            'Read: ${readable ? "ok" : "no"} | '
            'Write: ${writable ? "ok" : "no"}',
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
