import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/login_code_screen.dart';
import 'screens/chat_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ayztdzspijsqlrfgyhnh.supabase.co',
    anonKey: 'sb_publishable_uCUvGmHS9eRCKcDn6lg0wA_kN8VM6oE',
  );

  final prefs = await SharedPreferences.getInstance();
  final savedProfileId = prefs.getString('saved_profile_id');

  runApp(MyApp(savedProfileId: savedProfileId));
}

class MyApp extends StatelessWidget {
  final String? savedProfileId;

  const MyApp({super.key, this.savedProfileId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Бубоглазики',
      theme: AppTheme.lightTheme,
      home: savedProfileId == null 
          ? const LoginCodeScreen()
          : ChatListScreen(currentUserId: savedProfileId!),
      debugShowCheckedModeBanner: false,
    );
  }
}
