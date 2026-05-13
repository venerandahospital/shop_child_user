import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'sales_screen.dart';
import 'inventory_screen.dart';
import 'stores_screen.dart';
import 'settings_screen.dart';
import '../widgets/bottom_nav.dart';
import '../services/auth_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final _authService = AuthService();
  bool _showSettings = true;

  @override
  void initState() {
    super.initState();
    _loadUserTypeGate();
  }

  Future<void> _loadUserTypeGate() async {
    final userType = await _authService.getUserType();
    if (!mounted) return;
    setState(() {
      _showSettings = userType == 'LOCAL';
      final maxIndex = _showSettings ? 4 : 3;
      if (_currentIndex > maxIndex) _currentIndex = 0;
    });
  }

  List<Widget> get _screens => [
    const DashboardScreen(),
    const SalesScreen(),
    const InventoryScreen(),
    const StoresScreen(),
    if (_showSettings) const SettingsScreen(),
  ];

  Future<void> _onWillPop() async {
    // Instead of exiting the app from root, always take user to Dashboard.
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
  }

  Future<void> _handleNavTap(int index) async {
    // Require re-auth when opening Settings.
    if (_showSettings && index == 4) {
      final allowed = await _confirmPasswordForSettings();
      if (!mounted || !allowed) return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  Future<bool> _confirmPasswordForSettings() async {
    final profile = await _authService.getCurrentProfile();
    if (!mounted) return false;
    final currentPassword = (profile['password'] ?? '').trim();
    if (currentPassword.isEmpty) return true;

    var enteredPassword = '';
    var obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm password'),
            content: TextField(
              autofocus: true,
              obscureText: obscure,
              onChanged: (value) => enteredPassword = value,
              decoration: InputDecoration(
                labelText: 'Enter password',
                suffixIcon: IconButton(
                  onPressed: () {
                    setDialogState(() => obscure = !obscure);
                  },
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              onSubmitted: (_) => Navigator.of(context).pop(true),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return false;
    if (enteredPassword.trim() == currentPassword) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wrong password.')),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: _currentIndex,
        onTap: _handleNavTap,
        showSettings: _showSettings,
      ),
      ),
    );
  }
}

