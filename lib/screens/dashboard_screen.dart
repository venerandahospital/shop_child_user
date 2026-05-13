import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/item_image_upload_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../widgets/adaptive_card_text.dart';
import '../widgets/app_drawer.dart';
import '../widgets/section_page_title.dart';
import '../models/store.dart';
import '../models/sale.dart';
import 'inventory_screen.dart';
import 'sales_screen.dart';
import 'debts_screen.dart';
import 'clients_screen.dart';
import 'stores_screen.dart';
import 'expenses_screen.dart';
import 'stock_receipts_list_screen.dart';
import 'sales_history_screen.dart';
import 'reorder_screen.dart';
import 'services_screen.dart';
import 'assets_screen.dart';
import 'loans_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _db = LocalDbService.instance;
  final _appSettings = AppSettingsService.instance;
  final _auth = AuthService();
  static const _heroImageAsset = 'assets/images/dashboard_hero.png';
  Store? _currentStore;
  bool _loading = true;

  String _currencySymbol = 'USh';
  String _currentUserName = 'User';
  String _currentUserEmail = 'admin@shop.com';
  String _currentUserRole = 'ADMIN';
  String _profilePic = '';
  bool _uploadingProfilePic = false;

  double _todaySales = 0;
  int _todaySalesCount = 0;
  double _outstandingDebts = 0;
  double _overviewExpenses = 0;
  double _overviewReceives = 0;
  int _reorderCount = 0;
  _OverviewRange _overviewRange = _OverviewRange.today;
  bool _quickActionsExpanded = true;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _appSettings.shopNameNotifier.addListener(_onShopNameChanged);
    _db.transactionVersion.addListener(_onTransactionChanged);
    _loadCurrentUserName();
    _loadData();
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _appSettings.shopNameNotifier.removeListener(_onShopNameChanged);
    _db.transactionVersion.removeListener(_onTransactionChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  String get _heroTitle {
    return 'Welcome to ${_appSettings.shopName}';
  }

  String get _heroSubtitle {
    return 'Manage stock, sales, debts, and expenses in one place.';
  }

  void _onTransactionChanged() {
    if (!mounted) return;
    _loadData();
  }

  void _onShopNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadCurrentUserName() async {
    final profile = await _auth.getCurrentProfile();
    if (!mounted) return;
    final name = (profile['name'] ?? '').trim();
    setState(() {
      _currentUserName = name.isEmpty ? 'User' : name;
      _currentUserEmail = (profile['email'] ?? '').toString().trim().isEmpty
          ? 'admin@shop.com'
          : (profile['email']).toString().trim();
      _currentUserRole =
          (profile['role'] ?? 'ADMIN').toString().trim().toUpperCase();
      _profilePic = (profile['profilePic'] ?? '').toString().trim();
    });
  }

  Future<void> _uploadProfilePhoto() async {
    if (_uploadingProfilePic) return;
    setState(() => _uploadingProfilePic = true);
    try {
      final imageUrl =
          await ItemImageUploadService.instance.pickCompressAndUpload();
      final profile = await _auth.getCurrentProfile();
      final result = await _auth.updateProfile(
        name: (profile['name'] ?? _currentUserName).toString(),
        email: (profile['email'] ?? _currentUserEmail).toString(),
        profilePic: imageUrl,
      );
      if (!mounted) return;
      if (result.$1) {
        await _loadCurrentUserName();
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.$2)));
    } catch (e) {
      if (!mounted) return;
      final message = '$e'.contains('_UserCancelledException')
          ? 'Image selection cancelled.'
          : 'Photo upload failed: $e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _uploadingProfilePic = false);
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });
    try {
      final isRemote = await _auth.isRemoteUser();
      if (isRemote) {
        final analytics =
            await RemoteSyncService.instance.fetchDashboardAnalytics(
          range: _overviewRangeApiParam(),
        );
        final storeMap = analytics['store'];
        final remoteStore = storeMap is Map<String, dynamic>
            ? Store.fromMap(storeMap)
            : storeMap is Map
                ? Store.fromMap(Map<String, dynamic>.from(storeMap))
                : null;
        if (!mounted) return;
        setState(() {
          _currentStore = remoteStore ?? _currentStore;
          _todaySales = (analytics['salesTotal'] as num?)?.toDouble() ?? 0;
          _todaySalesCount = (analytics['salesCount'] as num?)?.toInt() ?? 0;
          _overviewExpenses =
              (analytics['expensesTotal'] as num?)?.toDouble() ?? 0;
          _overviewReceives =
              (analytics['receivesTotal'] as num?)?.toDouble() ?? 0;
          _outstandingDebts =
              (analytics['outstandingDebts'] as num?)?.toDouble() ?? 0;
          _reorderCount = (analytics['reorderCount'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
        return;
      }
      final defaultStore = await _db.getDefaultStore();
      final store = defaultStore ??
          Store(
            name: 'Main Store',
            description: 'Default store',
            isDefault: true,
          );

      Store? ensuredStore = defaultStore;
      if (defaultStore == null) {
        final id = await _db.upsertStore(store);
        ensuredStore = Store(
          id: id,
          name: store.name,
          description: store.description,
          isDefault: true,
          createdAt: store.createdAt,
        );
      }

      final allSalesFuture = _db.getAllSales();
      final expensesFuture = _db.getExpenses();
      final receiptsFuture = _db.getStockReceiptsWithDetails();
      final outstandingFuture = _db.getOutstandingDebtTotal();
      final reorderFuture = _db.getReorderCount();

      final allSales = await allSalesFuture;
      final filteredSales = _filterSalesByRange(allSales, _overviewRange);
      final todaySales = filteredSales.fold<double>(
        0,
        (sum, sale) => sum + sale.totalAmount,
      );
      final todaySalesCount = filteredSales.length;
      final expenses = await expensesFuture;
      final overviewExpenses = expenses
          .where((e) => _isInOverviewRange(e.createdAt, _overviewRange))
          .fold<double>(0, (sum, e) => sum + e.amount);
      final receiveRows = await receiptsFuture;
      final overviewReceives = receiveRows.fold<double>(0, (sum, row) {
        final dt = DateTime.tryParse((row['received_at'] as String?) ?? '');
        if (dt == null || !_isInOverviewRange(dt, _overviewRange)) return sum;
        return sum + ((row['total_cost'] as num?)?.toDouble() ?? 0);
      });
      final outstandingDebts = await outstandingFuture;
      final reorderCount = await reorderFuture;

      if (!mounted) return;
      setState(() {
        _currentStore = ensuredStore;
        _todaySales = todaySales;
        _todaySalesCount = todaySalesCount;
        _overviewExpenses = overviewExpenses;
        _overviewReceives = overviewReceives;
        _outstandingDebts = outstandingDebts;
        _reorderCount = reorderCount;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String _overviewRangeApiParam() {
    switch (_overviewRange) {
      case _OverviewRange.today:
        return 'today';
      case _OverviewRange.lastWeek:
        return 'lastweek';
      case _OverviewRange.lastMonth:
        return 'lastmonth';
      case _OverviewRange.all:
        return 'all';
    }
  }

  List<Sale> _filterSalesByRange(List<Sale> sales, _OverviewRange range) {
    if (range == _OverviewRange.all) return sales;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    DateTime start;
    DateTime end = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );

    switch (range) {
      case _OverviewRange.today:
        start = startOfToday;
        break;
      case _OverviewRange.lastWeek:
        start = startOfToday.subtract(const Duration(days: 6));
        break;
      case _OverviewRange.lastMonth:
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case _OverviewRange.all:
        start = DateTime(2000);
        break;
    }

    return sales.where((sale) {
      final created = sale.createdAt;
      return !created.isBefore(start) && !created.isAfter(end);
    }).toList();
  }

  bool _isInOverviewRange(DateTime created, _OverviewRange range) {
    if (range == _OverviewRange.all) return true;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    DateTime start;
    final end = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );

    switch (range) {
      case _OverviewRange.today:
        start = startOfToday;
        break;
      case _OverviewRange.lastWeek:
        start = startOfToday.subtract(const Duration(days: 6));
        break;
      case _OverviewRange.lastMonth:
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case _OverviewRange.all:
        start = DateTime(2000);
        break;
    }
    return !created.isBefore(start) && !created.isAfter(end);
  }

  void _setOverviewRange(_OverviewRange range) {
    if (_overviewRange == range) return;
    setState(() {
      _overviewRange = range;
    });
    _loadData();
  }

  String _overviewTitle() {
    switch (_overviewRange) {
      case _OverviewRange.today:
        return 'Today\'s overview';
      case _OverviewRange.lastWeek:
        return 'Last week overview';
      case _OverviewRange.lastMonth:
        return 'Last month overview';
      case _OverviewRange.all:
        return 'All time overview';
    }
  }

  String _salesCardTitle() {
    switch (_overviewRange) {
      case _OverviewRange.today:
        return 'Today sales';
      case _OverviewRange.lastWeek:
        return 'Weekly sales';
      case _OverviewRange.lastMonth:
        return 'Monthly sales';
      case _OverviewRange.all:
        return 'All sales';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2563eb), Color(0xFF1d4ed8)],
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'More',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Loans'),
                subtitle: const Text('Client loans & repayment dates'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoansScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF5181da),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle(
              style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ) ??
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
              child: const SectionPageTitle(pageTitle: 'Dashboard'),
            ),
            if (_currentStore != null)
              Text(
                _currentStore!.name,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.menu_open),
            tooltip: 'More',
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBannerCard(theme),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _quickActionsExpanded = !_quickActionsExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Quick actions',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Icon(
                              _quickActionsExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_quickActionsExpanded) ...[
                      const SizedBox(height: 16),
                      _buildQuickActions(context),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      _overviewTitle(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 0,
                            ),
                            label: const Text('Today'),
                            selected: _overviewRange == _OverviewRange.today,
                            selectedColor: Colors.lightGreen.shade100,
                            onSelected: (_) =>
                                _setOverviewRange(_OverviewRange.today),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 0,
                            ),
                            label: const Text('Last week'),
                            selected: _overviewRange == _OverviewRange.lastWeek,
                            selectedColor: Colors.lightGreen.shade100,
                            onSelected: (_) =>
                                _setOverviewRange(_OverviewRange.lastWeek),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 0,
                            ),
                            label: const Text('Last month'),
                            selected:
                                _overviewRange == _OverviewRange.lastMonth,
                            selectedColor: Colors.lightGreen.shade100,
                            onSelected: (_) =>
                                _setOverviewRange(_OverviewRange.lastMonth),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 0,
                            ),
                            label: const Text('All'),
                            selected: _overviewRange == _OverviewRange.all,
                            selectedColor: Colors.lightGreen.shade100,
                            onSelected: (_) =>
                                _setOverviewRange(_OverviewRange.all),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatsList(theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerCard(ThemeData theme) {
    return PhysicalShape(
      elevation: 6,
      color: Colors.transparent,
      shadowColor: Colors.blue.withValues(alpha: 0.25),
      clipper: _DownwardBottomClipper(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF5181da),
              Color(0xFF5181da),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back $_currentUserName',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _heroTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.yellow,
                            fontWeight: FontWeight.bold,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _heroSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFF5F5F5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 124,
                      height: 124,
                      child: Image.asset(
                        _heroImageAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.white.withValues(alpha: 0.72),
                          child: const Icon(
                            Icons.store_mall_directory_outlined,
                            size: 36,
                            color: Color(0xFF1D7A42),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsList(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      // Slightly taller cards to avoid bottom overflow on some screens.
      childAspectRatio: 1.02,
      children: [
        _buildStatCard(
          title: _salesCardTitle(),
          value: '$_currencySymbol${formatMoney(_todaySales)}',
          subtitle: '$_todaySalesCount receipts',
          icon: Icons.point_of_sale,
          color: Colors.green,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SalesHistoryScreen(),
              ),
            );
          },
        ),
        _buildStatCard(
          title: 'Outstanding debts',
          value: '$_currencySymbol${formatMoney(_outstandingDebts)}',
          subtitle: 'Tap to view details',
          icon: Icons.receipt_long,
          color: Colors.orange,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebtsScreen()),
            );
            if (!mounted) return;
            await _loadData();
          },
        ),
        _buildStatCard(
          title: 'Expenses',
          value: '$_currencySymbol${formatMoney(_overviewExpenses)}',
          subtitle: 'For selected period',
          icon: Icons.receipt_long,
          color: Colors.brown,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExpensesScreen()),
            );
          },
        ),
        _buildStatCard(
          title: 'Receives',
          value: '$_currencySymbol${formatMoney(_overviewReceives)}',
          subtitle: 'Stock receive value',
          icon: Icons.move_to_inbox,
          color: Colors.purple,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StockReceiptsListScreen()),
            );
          },
        ),
        _buildStatCard(
          title: 'Reorder',
          value: '$_reorderCount',
          subtitle: 'Items to reorder',
          icon: Icons.report_gmailerrorred,
          color: Colors.red,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ReorderScreen(),
              ),
            );
          },
        ),
        _buildStatCard(
          title: 'Service offered',
          value: (_currentStore?.description ?? '').trim().isNotEmpty
              ? _currentStore!.description!.trim()
              : 'Retail services',
          subtitle: 'Tap to manage stores',
          icon: Icons.miscellaneous_services,
          color: Colors.blue,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServicesScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final card = Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AdaptiveCardText(
              value,
              maxLines: 2,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1.1,
              ),
              minFontSize: 11,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: 8),
            AdaptiveCardText(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              minFontSize: 10,
            ),
            const SizedBox(height: 4),
            AdaptiveCardText(
              subtitle,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
              minFontSize: 9,
            ),
          ],
        ),
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      );
    }
    return card;
  }

  Widget _buildQuickActions(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: [
        _buildActionCard(
          title: 'New sale',
          icon: Icons.add_shopping_cart,
          color: Colors.green,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Debts',
          icon: Icons.account_balance_wallet,
          color: Colors.orange,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebtsScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Expenses',
          icon: Icons.receipt_long,
          color: Colors.brown,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExpensesScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Receive',
          icon: Icons.move_to_inbox,
          color: Colors.purple,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StockReceiptsListScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'New item',
          icon: Icons.inventory_2,
          color: Colors.blue,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InventoryScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Services',
          icon: Icons.miscellaneous_services,
          color: Colors.blue,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServicesScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Clients',
          icon: Icons.people_alt_outlined,
          color: Colors.teal,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClientsScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Assets',
          icon: Icons.apartment,
          color: Colors.cyan,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AssetsScreen()),
            );
          },
        ),
        _buildActionCard(
          title: 'Stores',
          icon: Icons.store,
          color: Colors.indigo,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StoresScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 8),
              AdaptiveCardText(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                minFontSize: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OverviewRange { today, lastWeek, lastMonth, all }

class _DownwardBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const curveDepth = 24.0;
    path.lineTo(0, size.height - curveDepth);
    path.quadraticBezierTo(
      size.width / 2,
      size.height + curveDepth,
      size.width,
      size.height - curveDepth,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
