import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io' show Platform;

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

    // 3. Запрос разрешений Firebase (iOS)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Запрос разрешения POST_NOTIFICATIONS для Android 13+ (API 33+)
    // Это КРИТИЧЕСКИ ВАЖНО — без этого уведомления не показываются на Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        print('FCM: POST_NOTIFICATIONS permission granted: $granted');
      }
    }

    // 5. Настройка каналов для Android
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

    // 6. Показывать foreground-уведомления от Firebase (для фонового/terminated обработчика)
    // Это позволяет системе автоматически показывать notification-часть
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
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
      print('FCM: токен сохранён для профиля $profileId → ${token.substring(0, 20)}...');
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

  /// Показывает локальное уведомление — работает и из notification, и из data-only
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    // Определяем заголовок и текст из notification или из data
    String? title = message.notification?.title;
    String? body = message.notification?.body;

    // Fallback: если notification-часть пустая, строим из data
    if (title == null || title.isEmpty) {
      final type = message.data['type'];
      if (type == 'call') {
        title = 'Входящий звонок';
        body = 'Вам звонит ${message.data['caller_name'] ?? 'кто-то'}';
      } else if (type == 'message') {
        title = message.data['sender_name'] ?? 'Новое сообщение';
        body = message.data['message_text'] ?? 'Новое сообщение';
      } else {
        title = 'Бубоглазики';
        body = 'Новое уведомление';
      }
    }

    // Определяем канал
    final type = message.data['type'];
    final channelId = type == 'call' ? 'calls_channel' : 'messages_channel';
    final channelName = type == 'call' ? 'Звонки' : 'Сообщения';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // уникальный ID
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: type == 'call' ? Importance.max : Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static Future<void> setupInteractions(Function(RemoteMessage) onMessageReceived) async {
    _onNotificationTapCallback = onMessageReceived;

    // 1. Слушаем сообщения, когда приложение открыто (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('FCM: onMessage foreground: ${message.data}');
      print('FCM: notification title: ${message.notification?.title}');
      print('FCM: notification body: ${message.notification?.body}');

      // Показываем уведомление вручную для Android (foreground)
      // Не зависим от message.notification?.android — оно часто null
      await _showLocalNotification(message);
      
      // Вызываем callback (для звонков чтобы экран сам открылся, если надо)
      if (message.data['type'] == 'call') {
        onMessageReceived(message);
      }
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
