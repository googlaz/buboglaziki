import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'call_screen.dart';
import '../services/jitsi_service.dart';
import '../services/notification_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  final bool isVideoCall;
  final String currentUserName;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.isVideoCall,
    required this.currentUserName,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    // Убираем уведомление о звонке — пользователь уже видит экран
    NotificationService.cancelCallNotification();
  }

  Future<void> _acceptCall() async {
    // Убираем уведомление
    await NotificationService.cancelCallNotification();
    // Даем права перед ответом, иначе зависнет
    await [Permission.microphone, Permission.camera].request();

    await _supabase.from('calls').update({'status': 'accepted'}).eq('id', widget.callId);

    if (mounted) {
      final url = JitsiService.getMeetingUrl(
        roomName: widget.callId.replaceAll('-', ''),
        userName: widget.currentUserName,
        isVideoCall: widget.isVideoCall,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            meetingUrl: url,
            isVideoCall: widget.isVideoCall,
            callId: widget.callId,
          ),
        ),
      );
    }
  }

  Future<void> _rejectCall() async {
    await NotificationService.cancelCallNotification();
    await _supabase.from('calls').update({'status': 'rejected'}).eq('id', widget.callId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const Icon(Icons.person, size: 100, color: Colors.white),
                const SizedBox(height: 20),
                Text(
                  widget.callerName,
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.isVideoCall ? 'Входящий видеозвонок...' : 'Входящий аудиозвонок...',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    FloatingActionButton(
                      onPressed: _rejectCall,
                      backgroundColor: Colors.red,
                      shape: const CircleBorder(),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 10),
                    const Text('Отклонить', style: TextStyle(color: Colors.white)),
                  ],
                ),
                Column(
                  children: [
                    FloatingActionButton(
                      onPressed: _acceptCall,
                      backgroundColor: Colors.green,
                      shape: const CircleBorder(),
                      child: Icon(widget.isVideoCall ? Icons.videocam : Icons.call, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 10),
                    const Text('Ответить', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
