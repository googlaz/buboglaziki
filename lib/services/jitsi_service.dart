class JitsiService {
  static String getMeetingUrl({
    required String roomName,
    required String userName,
    required bool isVideoCall,
  }) {
    // Делаем имя комнаты безопасным для Jitsi (иначе выдает The room is unsafe)
    final safeRoomName = 'bubofamily_$roomName' + (isVideoCall ? '_video' : '_audio');
    
    final config = [
      'config.startWithAudioMuted=false',
      'config.startWithVideoMuted=${!isVideoCall}',
      'config.startAudioOnly=${!isVideoCall}',
      'config.disableDeepLinking=true',
      'config.prejoinPageEnabled=false',
      'userInfo.displayName=$userName',
    ].join('&');

    return 'https://meet.ffmuc.net/$safeRoomName#$config';
  }
}
