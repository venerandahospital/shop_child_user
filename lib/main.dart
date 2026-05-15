// Child UI: a thin client. The mother (shop manager) app hosts the HTTP API and
// SQLite database; this process only renders UI, calls those endpoints, and keeps
// small in-memory copies of fetched data (see MotherDataCache / RemoteSyncService).
import 'package:flutter/material.dart';
import 'navigation/app_router.dart';
import 'services/low_stock_notification_service.dart';
import 'services/special_items_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SpecialItemsService.instance.ensureLoaded();
  await LowStockNotificationService.instance.initialize();
  await LowStockNotificationService.instance.requestPermissionIfNeeded();
  await LowStockNotificationService.instance.scheduleTwiceDailyLowStockAlerts();
  runApp(const ShopApp());
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Child UI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563eb),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF5181da),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      initialRoute: AppRouter.connect,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
