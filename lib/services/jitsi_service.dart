class JitsiService {
  static String getMeetingUrl({
    required String roomName,
    required String userName,
    required bool isVideoCall,
  }) {
    // Делаем имя комнаты безопасным для Jitsi (иначе выдает The room is unsafe)
    final safeRoomName = 'bubofamily_$roomName' + (isVideoCall ? '_video' : '_audio');

    // Имя пользователя нужно URL-encode, иначе кириллица и пробелы ломают URL
    final encodedName = Uri.encodeComponent(userName);

    final config = [
      'config.startWithAudioMuted=false',
      'config.startWithVideoMuted=${!isVideoCall}',
      'config.startAudioOnly=${!isVideoCall}',
      'config.disableDeepLinking=true',
      'config.prejoinPageEnabled=false',
      'userInfo.displayName=$encodedName',
    ].join('&');

    return 'https://meet.ffmuc.net/$safeRoomName#$config';
  }
}
