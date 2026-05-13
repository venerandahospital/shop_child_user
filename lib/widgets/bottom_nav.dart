import 'package:flutter/material.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool showSettings;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.showSettings = true,
  });

  @override
  Widget build(BuildContext context) {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.point_of_sale),
        label: 'Sales',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.inventory_2),
        label: 'Items',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.storefront),
        label: 'Stores',
      ),
      if (showSettings)
        const BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
    ];
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFF2563eb),
      unselectedItemColor: Colors.grey,
      items: items,
    );
  }
}

