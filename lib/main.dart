import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/login_code_screen.dart';
import 'screens/chat_list_screen.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Глобальное имя текущего пользователя — заполняется после логина
String currentUserDisplayName = 'Семьянин';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация локальных уведомлений (без Firebase/Google!)
  await NotificationService.initialize();

  await Supabase.initialize(
    url: 'https://ayztdzspijsqlrfgyhnh.supabase.co',
    anonKey: 'sb_publishable_uCUvGmHS9eRCKcDn6lg0wA_kN8VM6oE',
  );

  final prefs = await SharedPreferences.getInstance();
  final savedProfileId = prefs.getString('saved_profile_id');

  // Загружаем имя пользователя из базы
  if (savedProfileId != null) {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('display_name')
          .eq('id', int.parse(savedProfileId))
          .single();
      currentUserDisplayName = profile['display_name'] ?? 'Семьянин';
    } catch (_) {}
  }

  runApp(MyApp(savedProfileId: savedProfileId));
}

class MyApp extends StatelessWidget {
  final String? savedProfileId;

  const MyApp({super.key, this.savedProfileId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Бубоглазики',
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      home: savedProfileId == null 
          ? const LoginCodeScreen()
          : ChatListScreen(currentUserId: savedProfileId!),
      debugShowCheckedModeBanner: false,
    );
  }
}
