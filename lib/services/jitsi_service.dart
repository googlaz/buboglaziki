import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

class JitsiService {
  static final _jitsiMeetPlugin = JitsiMeet();

  static Future<void> joinMeeting({
    required String roomName,
    required String userName,
    required bool isVideoCall,
  }) async {
    var options = JitsiMeetConferenceOptions(
      room: roomName,
      serverURL: 'https://meet.jit.si',
      configOverrides: {
        "startWithAudioMuted": false,
        "startWithVideoMuted": !isVideoCall,
        "startAudioOnly": !isVideoCall,
      },
      featureFlags: {
        "unsaferoomwarning.enabled": false,
      },
      userInfo: JitsiMeetUserInfo(
        displayName: userName,
      ),
    );

    await _jitsiMeetPlugin.join(options);
  }
}
