import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'call_screen.dart';
import 'outgoing_call_screen.dart';
import 'incoming_call_screen.dart';
import '../services/jitsi_service.dart';
import '../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  final String currentUserId;
  final String? otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    required this.currentUserId,
    this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _currentUserName = 'Семьянин';
  RealtimeChannel? _incomingCallChannel;
  bool _isShowingIncomingCall = false;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _subscribeToIncomingCalls();
  }

  void _subscribeToIncomingCalls() {
    final receiverId = int.tryParse(widget.currentUserId);
    if (receiverId == null) return;

    _incomingCallChannel = _supabase
        .channel('chat_incoming_calls_${widget.currentUserId}_${widget.chatId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: receiverId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            if (record['status'] != 'ringing') return;
            if (_isShowingIncomingCall) return;

            final callId = record['id']?.toString();
            final callerId = record['caller_id']?.toString();
            if (callId == null || callerId == null) return;

            String callerName = 'Семьянин';
            try {
              final p = await _supabase
                  .from('profiles')
                  .select('display_name')
                  .eq('id', int.parse(callerId))
                  .single();
              callerName = p['display_name'] ?? 'Семьянин';
            } catch (_) {}

            if (!mounted) return;
            _isShowingIncomingCall = true;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IncomingCallScreen(
                  callId: callId,
                  callerName: callerName,
                  isVideoCall: false,
                  currentUserName: _currentUserName,
                ),
              ),
            ).then((_) => _isShowingIncomingCall = false);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _incomingCallChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchUserName() async {
    try {
      final res = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', widget.currentUserId)
          .single();
      setState(() {
        _currentUserName = res['display_name'];
      });
    } catch (_) {}
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    if ((text == null || text.trim().isEmpty) && imageUrl == null) return;
    
    final content = text?.trim();
    _messageController.clear();

    await _supabase.from('messages').insert({
      'chat_id': widget.chatId,
      'sender_id': widget.currentUserId,
      'content': content,
      'image_url': imageUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final fileExt = file.path.split('.').last;
    final fileName = '${const Uuid().v4()}.$fileExt';

    try {
      await _supabase.storage.from('family-media').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$fileExt'),
          );

      final imageUrl = _supabase.storage.from('family-media').getPublicUrl(fileName);
      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки фото: $e')),
        );
      }
    }
  }

  void _startCall(bool isVideo) async {
    if (widget.otherUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Звонки доступны только в личном чате')),
      );
      return;
    }
    try {
      final otherProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', widget.otherUserId!)
          .single();

      final receiverId = otherProfile['id']?.toString() ?? '';
      final receiverName = otherProfile['display_name'] ?? 'Семья';
      final receiverUrl = otherProfile['avatar_url'] ?? '';
      final receiverToken = otherProfile['fcm_token'] ?? '';

      if (receiverToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Собеседник ещё не открывал приложение. Попросите его открыть Бубоглазики!')),
        );
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OutgoingCallScreen(
              receiverId: receiverId,
              receiverName: receiverName,
              receiverAvatarUrl: receiverUrl,
              receiverFcmToken: receiverToken,
              callerId: widget.currentUserId,
              callerName: _currentUserName,
              isVideoCall: isVideo,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка звонка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, size: 30),
            tooltip: 'Позвонить',
            onPressed: () => _startCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, size: 30),
            tooltip: 'Видеозвонок',
            onPressed: () => _startCall(true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('chat_id', widget.chatId)
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final messages = snapshot.data ?? [];
                
                return Container(
                  color: AppTheme.chatBackgroundColor,
                  child: ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    itemCount: messages.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['sender_id'] == widget.currentUserId;
                      final text = msg['content'];
                      final imageUrl = msg['image_url'];
                      final timestamp = msg['created_at'] != null
                          ? DateTime.parse(msg['created_at'])
                          : DateTime.now();
                      final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

                      return _MessageBubble(
                        isMe: isMe,
                        text: text,
                        imageUrl: imageUrl,
                        timeStr: timeStr,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library, size: 28, color: Colors.grey),
                  onPressed: _pickAndUploadImage,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(fontSize: 18),
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение...',
                        hintStyle: TextStyle(fontSize: 18, color: Colors.grey),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  radius: 24,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 22),
                    onPressed: () => _sendMessage(text: _messageController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final String? text;
  final String? imageUrl;
  final String timeStr;

  const _MessageBubble({
    required this.isMe,
    this.text,
    this.imageUrl,
    required this.timeStr,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isMe ? 56 : 12,
          right: isMe ? 12 : 56,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.sentMessageColor : AppTheme.receivedMessageColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl!,
                    width: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return SizedBox(
                        height: 150,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        height: 100,
                        child: Center(
                          child: Icon(Icons.broken_image, size: 40, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: text != null && text!.isNotEmpty
                      ? Text(
                          text!,
                          style: const TextStyle(fontSize: 18, height: 1.3),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.timestampColor,
                      ),
                    ),
                    if (isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(
                          Icons.done_all,
                          size: 14,
                          color: AppTheme.primaryColor,
                        ),
                      ),
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
