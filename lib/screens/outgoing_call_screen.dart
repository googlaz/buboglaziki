import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/fcm_sender.dart';
import 'call_screen.dart';
import '../services/jitsi_service.dart';

class OutgoingCallScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String receiverAvatarUrl;
  final String receiverFcmToken;
  final String callerId;
  final String callerName;
  final bool isVideoCall;

  const OutgoingCallScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    required this.receiverAvatarUrl,
    required this.receiverFcmToken,
    required this.callerId,
    required this.callerName,
    required this.isVideoCall,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  final _supabase = Supabase.instance.client;
  String? _callId;
  RealtimeChannel? _callSubscription;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<void> _startCall() async {
    try {
      // 0. Запрашиваем разрешения до открытия WebView — без них Jitsi не захватит аудио/видео
      final permissions = [Permission.microphone];
      if (widget.isVideoCall) permissions.add(Permission.camera);
      await permissions.request();

      // 1. Создаем запись в базе
      final response = await _supabase.from('calls').insert({
        'caller_id': int.parse(widget.callerId),
        'receiver_id': int.parse(widget.receiverId),
        'status': 'ringing',
      }).select().single();

      _callId = response['id'];

      // 2. Отправляем Push-уведомление через Firebase чтобы разбудить второй телефон
      if (widget.receiverFcmToken.isNotEmpty) {
        await FcmSender.sendCallNotification(
          targetToken: widget.receiverFcmToken,
          callerName: widget.callerName,
          callId: _callId!,
          isVideo: widget.isVideoCall,
        );
      }

      // 3. Начинаем слушать ответ
      _callSubscription = _supabase
          .channel('public:calls:id=eq.$_callId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _callId,
            ),
            callback: (payload) {
              final newStatus = payload.newRecord['status'];
              if (newStatus == 'accepted') {
                _onCallAccepted();
              } else if (newStatus == 'rejected') {
                _onCallRejected();
              }
            },
          )
          .subscribe();

    } catch (e) {
      print('Ошибка инициализации звонка: \$e');
      if (mounted) Navigator.pop(context);
    }
  }

  void _onCallAccepted() {
    if (!mounted) return;
    _callSubscription?.unsubscribe();

    // Генерируем уникальную комнату на основе ID звонка
    final url = JitsiService.getMeetingUrl(
      roomName: _callId!.replaceAll('-', ''),
      userName: widget.callerName,
      isVideoCall: widget.isVideoCall,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          meetingUrl: url,
          isVideoCall: widget.isVideoCall,
          callId: _callId,
        ),
      ),
    );
  }

  void _onCallRejected() {
    if (!mounted) return;
    _callSubscription?.unsubscribe();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Звонок сброшен')),
    );
  }

  void _endCall() async {
    if (_callId != null) {
      await _supabase.from('calls').update({'status': 'ended'}).eq('id', _callId!);
    }
    _callSubscription?.unsubscribe();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callSubscription?.unsubscribe();
    super.dispose();
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
                CircleAvatar(
                  radius: 70,
                  backgroundImage: widget.receiverAvatarUrl.isNotEmpty
                      ? NetworkImage(widget.receiverAvatarUrl)
                      : null,
                  child: widget.receiverAvatarUrl.isEmpty
                      ? const Icon(Icons.person, size: 70)
                      : null,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.receiverName,
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Звоним...',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                ),
              ],
            ),
            FloatingActionButton(
              onPressed: _endCall,
              backgroundColor: Colors.red,
              shape: const CircleBorder(),
              child: const Icon(Icons.call_end, color: Colors.white, size: 36),
            ),
          ],
        ),
      ),
    );
  }
}
