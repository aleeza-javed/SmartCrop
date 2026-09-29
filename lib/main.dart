import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'screens/notifications_screen.dart';
import 'screens/splash_screen.dart';

/// Lets a tray-notification tap open the history screen from outside a widget
/// callback. Kept here so `NotificationService` never imports a screen.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Threshold alerts. Requested before the first frame so the permission
  // prompt is not competing with the splash animation; a refusal only
  // disables notifications, the app runs either way.
  //
  // The tap callback only helps when the app is already running; a cold start
  // from the tray lands on the splash screen, which routes to the dashboard
  // on its own.
  await NotificationService.instance.init(
    onTap: () => _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    ),
  );
  runApp(const SmartCropApp());
}

class SmartCropApp extends StatelessWidget {
  const SmartCropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartCrop',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
