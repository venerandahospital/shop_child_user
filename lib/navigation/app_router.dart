import 'package:flutter/material.dart';
import '../screens/child_connect_screen.dart';
import '../screens/child_login_screen.dart';
import '../screens/child_signup_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../services/auth_service.dart';

class AppRouter {
  static const String login = '/login';
  static const String signup = '/signup';
  static const String main = '/main';
  static const String connect = '/connect';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const ChildLoginScreen());
      case signup:
        return MaterialPageRoute(builder: (_) => const ChildSignupScreen());
      case main:
        return MaterialPageRoute(builder: (_) => const MainNavigationScreen());
      case connect:
        return MaterialPageRoute(builder: (_) => const ChildConnectScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${routeSettings.name}'),
            ),
          ),
        );
    }
  }

  static Future<void> checkAuthAndNavigate(BuildContext context) async {
    final authService = AuthService();
    final isLoggedIn = await authService.isLoggedIn();

    if (isLoggedIn) {
      Navigator.of(context).pushReplacementNamed(main);
    } else {
      Navigator.of(context).pushReplacementNamed(login);
    }
  }
}
