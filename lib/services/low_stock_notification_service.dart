import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'local_db_service.dart';
import 'mother_data_cache.dart';

class LowStockNotificationService {
  LowStockNotificationService._();

  static final LowStockNotificationService instance =
      LowStockNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final LocalDbService _db = LocalDbService.instance;
  bool _initialized = false;

  static const int _morningId = 91001;
  static const int _eveningId = 91002;
  static const String _channelId = 'low_stock_alerts';

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> requestPermissionIfNeeded() async {
    if (kIsWeb) return;
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> scheduleTwiceDailyLowStockAlerts() async {
    if (kIsWeb) return;
    await initialize();
    final lowStock = MotherDataCache.instance.itemsApplied
        ? MotherDataCache.instance.getReorderItems()
        : await _db.getReorderItems();
    final count = lowStock.length;
    final body = count > 0
        ? 'You have $count low-stock item(s). Open Inventory to restock.'
        : 'No low-stock items right now. We will keep monitoring.';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Low stock alerts',
        channelDescription: 'Twice-daily low stock reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.cancel(_morningId);
    await _plugin.cancel(_eveningId);

    await _plugin.zonedSchedule(
      _morningId,
      'Low stock reminder',
      body,
      _nextInstanceOf(hour: 9, minute: 0),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    await _plugin.zonedSchedule(
      _eveningId,
      'Low stock reminder',
      body,
      _nextInstanceOf(hour: 18, minute: 0),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOf({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) {
      when = when.add(const Duration(days: 1));
    }
    return when;
  }
}

