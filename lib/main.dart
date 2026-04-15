import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/login_code_screen.dart';
import 'screens/chat_list_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'services/fcm_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/incoming_call_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await FcmService.initialize();

  // Ловим уведомления: когда мы внутри приложения, в фоне или когда закрыто
  await FcmService.setupInteractions((RemoteMessage message) {
    if (message.data['type'] == 'call') {
      final String? callId = message.data['call_id'];
      final String? callerName = message.data['caller_name'];
      final bool isVideo = message.data['is_video'] == 'true';

      if (callId != null && callerName != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callId: callId,
              callerName: callerName,
              isVideoCall: isVideo,
              currentUserName: 'Семьянин', // Можно заменить на реальное из базы, если надо
            ),
          ),
        );
      }
    }
  });

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
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      home: savedProfileId == null 
          ? const LoginCodeScreen()
          : ChatListScreen(currentUserId: savedProfileId!),
      debugShowCheckedModeBanner: false,
    );
  }
}
