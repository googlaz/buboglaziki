import 'package:url_launcher/url_launcher.dart';

class JitsiService {
  static Future<void> joinMeeting({
    required String roomName,
    required String userName,
    required bool isVideoCall,
  }) async {
    // Формируем URL для Jitsi Meet с параметрами пользователя
    final config = [
      'config.startWithAudioMuted=false',
      'config.startWithVideoMuted=${!isVideoCall}',
      'config.startAudioOnly=${!isVideoCall}',
      'config.disableDeepLinking=true',
      'userInfo.displayName=$userName',
    ].join('&');

    final url = Uri.parse('https://meet.jit.si/$roomName#$config');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Не удалось открыть Jitsi Meet');
    }
  }
}
