import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/item_image_upload_service.dart';
import '../screens/child_login_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/special_items_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/unit_management_screen.dart';
import '../screens/sales_screen.dart';
import '../screens/expenses_screen.dart';
import '../screens/expense_category_screen.dart';
import '../screens/services_screen.dart';
import '../screens/sales_history_screen.dart';
import '../screens/debts_screen.dart';
import '../screens/loans_screen.dart';
import '../screens/clients_screen.dart';
import '../screens/stock_receipts_list_screen.dart';
import '../screens/stores_screen.dart';
import '../screens/support_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final AuthService _authService = AuthService();
  String? _username;
  String? _userEmail;
  String _userRole = 'ADMIN';
  String _profilePic = '';
  bool _uploadingProfilePic = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final profile = await _authService.getCurrentProfile();
    if (!mounted) return;

    setState(() {
      _username = (profile['name'] ?? '').toString().trim().isEmpty
          ? 'Shop Admin'
          : (profile['name']).toString().trim();
      _userEmail = (profile['email'] ?? '').toString().trim().isEmpty
          ? 'admin@shop.com'
          : (profile['email']).toString().trim();
      _userRole = (profile['role'] ?? 'ADMIN').toString().trim().toUpperCase();
      _profilePic = (profile['profilePic'] ?? '').toString().trim();
    });
  }

  Future<void> _uploadProfilePhoto() async {
    if (_uploadingProfilePic) return;
    setState(() => _uploadingProfilePic = true);
    try {
      final imageUrl = await ItemImageUploadService.instance.pickCompressAndUpload();
      final current = await _authService.getCurrentProfile();
      final result = await _authService.updateProfile(
        name: (current['name'] ?? _username ?? 'Shop Admin').toString(),
        email: (current['email'] ?? _userEmail ?? 'admin@shop.com').toString(),
        profilePic: imageUrl,
      );
      if (!mounted) return;
      if (result.$1) {
        await _loadUserInfo();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.$2)));
    } catch (e) {
      if (!mounted) return;
      final message = '$e'.contains('_UserCancelledException')
          ? 'Image selection cancelled.'
          : 'Photo upload failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _uploadingProfilePic = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ChildLoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(
              top: 60,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2563eb),
                  Color(0xFF1d4ed8),
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white,
                            backgroundImage:
                                _profilePic.isNotEmpty ? NetworkImage(_profilePic) : null,
                            child: _profilePic.isEmpty
                                ? Text(
                                    (_username ?? 'S')[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563eb),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _uploadingProfilePic ? null : _uploadProfilePhoto,
                            icon: _uploadingProfilePic
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(
                                    Icons.photo_camera_outlined,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              _uploadingProfilePic ? 'Uploading...' : 'Edit photo',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 0),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              alignment: Alignment.centerLeft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _username ?? 'Shop Admin',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _userEmail ?? 'admin@shop.com',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _userRole,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListTileTheme(
              data: const ListTileThemeData(
                dense: true,
                visualDensity: VisualDensity(vertical: -2),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                ListTile(
                  leading:
                      const Icon(Icons.dashboard, color: Color(0xFF2563eb)),
                  title: const Text('Dashboard'),
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.inventory_2, color: Color(0xFF2563eb)),
                  title: const Text('Products'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InventoryScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.star_outline, color: Color(0xFF2563eb)),
                  title: const Text('Special items'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SpecialItemsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.category, color: Color(0xFF2563eb)),
                  title: const Text('Category'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.straighten, color: Color(0xFF2563eb)),
                  title: const Text('Unit Management'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UnitManagementScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.point_of_sale, color: Color(0xFF2563eb)),
                  title: const Text('POS'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SalesScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.account_balance_wallet,
                    color: Color(0xFF2563eb),
                  ),
                  title: const Text('Expense'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.label, color: Color(0xFF2563eb)),
                  title: const Text('Expense Category'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ExpenseCategoryScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.miscellaneous_services,
                    color: Color(0xFF2563eb),
                  ),
                  title: const Text('Services'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServicesScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.bar_chart, color: Color(0xFF2563eb)),
                  title: const Text('Reports'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.receipt_long, color: Color(0xFF2563eb)),
                  title: const Text('Debts'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DebtsScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.savings_outlined,
                    color: Color(0xFF2563eb),
                  ),
                  title: const Text('Loans'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoansScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.people, color: Color(0xFF2563eb)),
                  title: const Text('Peoples'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ClientsScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.warehouse, color: Color(0xFF2563eb)),
                  title: const Text('Warehouse'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StockReceiptsListScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.store, color: Color(0xFF2563eb)),
                  title: const Text('Stores'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StoresScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.support_agent, color: Color(0xFF2563eb)),
                  title: const Text('Support'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SupportScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.person, color: Color(0xFF2563eb)),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    )
                        .then((_) {
                      if (mounted) _loadUserInfo();
                    });
                  },
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.help_outline, color: Color(0xFF2563eb)),
                  title: const Text('Help & Support'),
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Help & Support - coming soon'),
                      ),
                    );
                  },
                ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _handleLogout,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Logout',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.of(context).pop();
                    showAboutDialog(
                      context: context,
                      applicationName: 'Veneranda Shop',
                      applicationVersion: '1.0.0',
                      applicationIcon: const Icon(
                        Icons.shopping_bag,
                        size: 40,
                        color: Color(0xFF2563eb),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFF2563eb),
                        ),
                        SizedBox(width: 6),
                        Text('About us'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
