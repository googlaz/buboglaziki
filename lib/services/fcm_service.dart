import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    await _localNotifications.initialize(initializationSettings);

    // 3. Запрос разрешений
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Настройка канала для Android (чтобы всплывало сверху)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'calls_channel',
      'Звонки',
      description: 'Уведомления о входящих вызовах',
      importance: Importance.max,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
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

  static void setupInteractions(Function(RemoteMessage) onMessageReceived) {
    // Слушаем сообщения, когда приложение открыто
    FirebaseMessaging.onMessage.listen(onMessageReceived);

    // Слушаем клик по уведомлению
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: onMessageOpenedApp: ${message.data}');
    });
  }
}
