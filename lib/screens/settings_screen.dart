import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/app_router.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../widgets/section_page_title.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kLowStockAlertsKey = 'settings_low_stock_alerts';

  final _authService = AuthService();
  final _appSettings = AppSettingsService.instance;
  final _shopNameController = TextEditingController();
  final _currencyController = TextEditingController(text: 'USh');

  bool _showFixedDecimals = false;
  bool _lowStockAlerts = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _shopNameController.text = _appSettings.shopName;
      _currencyController.text = _appSettings.currencySymbol;
      _showFixedDecimals = _appSettings.showFixedDecimals;
      _lowStockAlerts = prefs.getBool(_kLowStockAlertsKey) ?? true;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await _appSettings.setShopName(_shopNameController.text.trim());
    await _appSettings.setCurrencySymbol(_currencyController.text.trim());
    await _appSettings.setShowFixedDecimals(_showFixedDecimals);
    await prefs.setBool(_kLowStockAlertsKey, _lowStockAlerts);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const SectionPageTitle(pageTitle: 'Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Shop',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _shopNameController,
                  decoration: const InputDecoration(
                    labelText: 'Shop name',
                    hintText: 'e.g. Main Street Supermarket',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _currencyController,
                  decoration: const InputDecoration(
                    labelText: 'Currency symbol',
                    hintText: 'e.g. USh, NGN, KES',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show fixed 2 decimals (e.g. 25.00)'),
                  value: _showFixedDecimals,
                  onChanged: (value) => setState(() => _showFixedDecimals = value),
                ),
                const SizedBox(height: 24),
                Text(
                  'Alerts',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Low stock alerts'),
                  subtitle: const Text(
                    'Highlight items that are out of stock or below reorder level',
                  ),
                  value: _lowStockAlerts,
                  onChanged: (value) => setState(() => _lowStockAlerts = value),
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Profile'),
                  subtitle: const Text('Edit account information'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _logout,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
