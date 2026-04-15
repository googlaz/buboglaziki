import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
  // Здесь мы можем логику для пробуждения экрана звонка, если нужно
}

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Инициализация Firebase (уже сделана в main)
    
    // 2. Обработка фоновых сообщений
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Настройка локальных уведомлений
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _localNotifications.initialize(initializationSettings);

    // 4. Запрос разрешений
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 5. Настройка канала для Android (чтобы всплывало сверху)
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

  static void setupInteractions(Function(RemoteMessage) onMessageReceived) {
    // Слушаем сообщения, когда приложение открыто
    FirebaseMessaging.onMessage.listen(onMessageReceived);

    // Слушаем клик по уведомлению
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
    });
  }
}
