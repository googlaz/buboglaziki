import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Обработка фоновых сообщений
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Настройка локальных уведомлений
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
        
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!);
            // Convert to a format that looks like RemoteMessage to pass to main
            _onNotificationTapCallback?.call(RemoteMessage(data: Map<String, dynamic>.from(data)));
          } catch (e) {
            print('FCM: Error parsing local notification payload: $e');
          }
        }
      },
    );

    // 3. Запрос разрешений
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Настройка каналов для Android
    const AndroidNotificationChannel callsChannel = AndroidNotificationChannel(
      'calls_channel',
      'Звонки',
      description: 'Уведомления о входящих вызовах',
      importance: Importance.max,
      playSound: true,
    );

    const AndroidNotificationChannel messagesChannel = AndroidNotificationChannel(
      'messages_channel',
      'Сообщения',
      description: 'Новые сообщения',
      importance: Importance.high,
      playSound: true,
    );

    final androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(callsChannel);
    await androidImplementation?.createNotificationChannel(messagesChannel);
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Сохраняет FCM-токен в базу Supabase для указанного профиля.
  /// profileId должен быть числом (int) — как в таблице profiles.
  static Future<void> saveTokenToDb(String profileId) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        print('FCM: токен не получен (разрешение не дано или нет Google Play Services)');
        return;
      }
      final numericId = int.tryParse(profileId);
      if (numericId == null) {
        print('FCM: некорректный profileId: $profileId');
        return;
      }
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', numericId);
      print('FCM: токен сохранён для профиля $profileId');
    } catch (e) {
      print('FCM: ошибка сохранения токена: $e');
    }
  }

  /// Вызывать после логина — будет авто-обновлять токен при его ротации Firebase.
  static void listenTokenRefresh(String profileId) {
    _messaging.onTokenRefresh.listen((newToken) async {
      print('FCM: токен обновился, сохраняем...');
      await saveTokenToDb(profileId);
    });
  }

  static Function(RemoteMessage)? _onNotificationTapCallback;

  static Future<void> setupInteractions(Function(RemoteMessage) onMessageReceived) async {
    _onNotificationTapCallback = onMessageReceived;

    // 1. Слушаем сообщения, когда приложение открыто (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FCM: onMessage foreground: ${message.data}');
      // Показываем уведомление вручную для Android
      final notification = message.notification;
      final android = message.notification?.android;
      
      if (notification != null && android != null) {
        final channelId = android.channelId ?? 'messages_channel';
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelId == 'calls_channel' ? 'Звонки' : 'Сообщения',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
      
      // Вызываем callback (для звонков чтобы экран сам открылся, если надо)
      onMessageReceived(message);
    });

    // 2. Слушаем клик по уведомлению, когда приложение было в фоне (background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: onMessageOpenedApp: ${message.data}');
      onMessageReceived(message);
    });

    // 3. Отлавливаем уведомление, которое запустило полностью закрытое приложение (terminated)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print('FCM: getInitialMessage: ${initialMessage.data}');
      // Даем небольшую задержку, чтобы Flutter и NavigatorKey успели инициализироваться
      Future.delayed(const Duration(milliseconds: 800), () {
        onMessageReceived(initialMessage);
      });
    }
  }
}
