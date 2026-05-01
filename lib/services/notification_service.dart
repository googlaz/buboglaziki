import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' show Platform;

/// Сервис локальных уведомлений — показывает уведомления БЕЗ Firebase/Google.
/// Работает через Supabase Realtime + flutter_local_notifications.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Фиксированный ID для звонков (чтобы можно было отменить)
  static const int callNotificationId = 99999;

  /// ID чата, который пользователь сейчас просматривает.
  /// Если не null — не показываем уведомления для этого чата.
  static String? activeOpenChatId;

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Запрос разрешения на Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    }

    // Создание каналов
    const callsChannel = AndroidNotificationChannel(
      'calls_channel',
      'Звонки',
      description: 'Уведомления о входящих вызовах',
      importance: Importance.max,
      playSound: true,
    );
    const messagesChannel = AndroidNotificationChannel(
      'messages_channel',
      'Сообщения',
      description: 'Новые сообщения',
      importance: Importance.high,
      playSound: true,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(callsChannel);
    await androidImpl?.createNotificationChannel(messagesChannel);

    _initialized = true;
  }

  /// Показать уведомление о новом сообщении
  static Future<void> showMessageNotification({
    required String senderName,
    required String messageText,
    required String chatId,
  }) async {
    // Не показываем уведомление, если пользователь уже в этом чате
    if (activeOpenChatId == chatId) return;

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      senderName,
      messageText.isEmpty ? '📷 Фотография' : messageText,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages_channel',
          'Сообщения',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
        ),
      ),
    );
  }

  /// Показать уведомление о звонке
  static Future<void> showCallNotification({
    required String callerName,
  }) async {
    await _plugin.show(
      callNotificationId,
      'Входящий звонок',
      'Вам звонит $callerName',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'calls_channel',
          'Звонки',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
        ),
      ),
    );
  }

  /// Отменить уведомление о звонке
  static Future<void> cancelCallNotification() async {
    await _plugin.cancel(callNotificationId);
  }
}
