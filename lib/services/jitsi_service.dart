class JitsiService {
  static String getMeetingUrl({
    required String roomName,
    required String userName,
    required bool isVideoCall,
  }) {
    final config = [
      'config.startWithAudioMuted=false',
      'config.startWithVideoMuted=${!isVideoCall}',
      'config.startAudioOnly=${!isVideoCall}',
      'config.disableDeepLinking=true',
      'userInfo.displayName=$userName',
    ].join('&');

    return 'https://meet.jit.si/$roomName#$config';
  }
}
