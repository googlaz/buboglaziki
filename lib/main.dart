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
import 'screens/chat_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Глобальное имя текущего пользователя — заполняется после логина
String currentUserDisplayName = 'Семьянин';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await FcmService.initialize();

  await Supabase.initialize(
    url: 'https://ayztdzspijsqlrfgyhnh.supabase.co',
    anonKey: 'sb_publishable_uCUvGmHS9eRCKcDn6lg0wA_kN8VM6oE',
  );

  final prefs = await SharedPreferences.getInstance();
  final savedProfileId = prefs.getString('saved_profile_id');

  // Загружаем имя пользователя из базы, чтобы передавать его в IncomingCallScreen
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
              currentUserName: currentUserDisplayName,
            ),
          ),
        );
      }
    } else if (message.data['type'] == 'message') {
      final String? chatId = message.data['chat_id'];
      if (chatId != null && savedProfileId != null) {
        final isGroup = chatId == 'family_group';
        String? targetUserId;
        if (!isGroup) {
          final ids = chatId.split('_');
          targetUserId = ids.firstWhere((id) => id != savedProfileId, orElse: () => '');
          if (targetUserId.isEmpty) targetUserId = null;
        }

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: chatId,
              title: isGroup ? 'Вся семья' : 'Диалог',
              currentUserId: savedProfileId,
              otherUserId: targetUserId,
            ),
          ),
        );
      }
    }
  });

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
