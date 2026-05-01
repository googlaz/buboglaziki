import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io' show Platform;

/// Фиксированный ID для уведомления о звонке — чтобы можно было его отменить
const int _callNotificationId = 99999;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("FCM BG: background message received: ${message.data}");

  // В фоне показываем уведомление вручную через flutter_local_notifications
  final plugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await plugin.initialize(initSettings);

  final type = message.data['type'];
  String title;
  String body;

  if (type == 'call') {
    title = 'Входящий звонок';
    body = 'Вам звонит ${message.data['caller_name'] ?? 'кто-то'}';
  } else if (type == 'message') {
    title = message.data['sender_name'] ?? 'Новое сообщение';
    body = message.data['message_text'] ?? '';
    if (body.isEmpty) body = 'Новое сообщение';
  } else {
    title = 'Бубоглазики';
    body = 'Новое уведомление';
  }

  final channelId = type == 'call' ? 'calls_channel' : 'messages_channel';
  final channelName = type == 'call' ? 'Звонки' : 'Сообщения';
  final notifId = type == 'call'
      ? _callNotificationId
      : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  await plugin.show(
    notifId,
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

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

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
            _onNotificationTapCallback
                ?.call(RemoteMessage(data: Map<String, dynamic>.from(data)));
          } catch (e) {
            print('FCM: Error parsing local notification payload: $e');
          }
        }
      },
    );

    // 3. Запрос разрешений Firebase (iOS + Android 13+ через Firebase SDK)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('FCM: Firebase permission status: ${settings.authorizationStatus}');

    // 4. Запрос разрешения POST_NOTIFICATIONS для Android 13+ (API 33+)
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        print('FCM: POST_NOTIFICATIONS permission granted: $granted');
      }
    }

    // 5. Настройка каналов для Android
    const AndroidNotificationChannel callsChannel =
        AndroidNotificationChannel(
      'calls_channel',
      'Звонки',
      description: 'Уведомления о входящих вызовах',
      importance: Importance.max,
      playSound: true,
    );

    const AndroidNotificationChannel messagesChannel =
        AndroidNotificationChannel(
      'messages_channel',
      'Сообщения',
      description: 'Новые сообщения',
      importance: Importance.high,
      playSound: true,
    );

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(callsChannel);
    await androidImplementation?.createNotificationChannel(messagesChannel);
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Сохраняет FCM-токен в базу Supabase для указанного профиля.
  static Future<void> saveTokenToDb(String profileId) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        print('FCM: токен не получен');
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

  /// Авто-обновление токена при его ротации Firebase.
  static void listenTokenRefresh(String profileId) {
    _messaging.onTokenRefresh.listen((newToken) async {
      print('FCM: токен обновился, сохраняем...');
      await saveTokenToDb(profileId);
    });
  }

  static Function(RemoteMessage)? _onNotificationTapCallback;

  /// Отменяет уведомление о звонке (когда звонок завершён/отклонён)
  static Future<void> cancelCallNotification() async {
    await _localNotifications.cancel(_callNotificationId);
    print('FCM: уведомление о звонке отменено');
  }

  /// Показывает локальное уведомление — для foreground
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final type = message.data['type'];
    String title;
    String body;

    // Берём из notification, если есть, иначе из data
    if (message.notification?.title != null &&
        message.notification!.title!.isNotEmpty) {
      title = message.notification!.title!;
      body = message.notification?.body ?? '';
    } else if (type == 'call') {
      title = 'Входящий звонок';
      body = 'Вам звонит ${message.data['caller_name'] ?? 'кто-то'}';
    } else if (type == 'message') {
      title = message.data['sender_name'] ?? 'Новое сообщение';
      body = message.data['message_text'] ?? 'Новое сообщение';
    } else {
      title = 'Бубоглазики';
      body = 'Новое уведомление';
    }

    final channelId = type == 'call' ? 'calls_channel' : 'messages_channel';
    final channelName = type == 'call' ? 'Звонки' : 'Сообщения';
    final notifId = type == 'call'
        ? _callNotificationId
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _localNotifications.show(
      notifId,
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
    print('FCM: показано уведомление: "$title" — "$body"');
  }

  static Future<void> setupInteractions(
      Function(RemoteMessage) onMessageReceived) async {
    _onNotificationTapCallback = onMessageReceived;

    // 1. Foreground: получаем сообщения, когда приложение открыто
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('FCM: ═══ onMessage FOREGROUND ═══');
      print('FCM: data: ${message.data}');
      print('FCM: notification: ${message.notification?.title} / ${message.notification?.body}');

      // Показываем уведомление вручную
      await _showLocalNotification(message);

      // Для звонков сразу открываем экран входящего вызова
      if (message.data['type'] == 'call') {
        onMessageReceived(message);
      }
    });

    // 2. Клик по уведомлению, когда приложение было в фоне
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: ═══ onMessageOpenedApp ═══');
      print('FCM: data: ${message.data}');
      onMessageReceived(message);
    });

    // 3. Уведомление, которое запустило закрытое приложение
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print('FCM: ═══ getInitialMessage ═══');
      print('FCM: data: ${initialMessage.data}');
      Future.delayed(const Duration(milliseconds: 800), () {
        onMessageReceived(initialMessage);
      });
    }
  }
}
