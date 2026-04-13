import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../services/jitsi_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  final String currentUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    required this.currentUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _currentUserName = 'Семьянин';

  @override
  void initState() {
    super.initState();
    _fetchUserName();
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
    try {
      await JitsiService.joinMeeting(
        roomName: widget.chatId.replaceAll('_', '').replaceAll('-', ''),
        userName: _currentUserName,
        isVideoCall: isVideo,
      );
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
                
                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == widget.currentUserId;
                    final text = msg['content'];
                    final imageUrl = msg['image_url'];

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF90EE90) : Colors.white,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe ? const Radius.circular(0) : null,
                            bottomLeft: !isMe ? const Radius.circular(0) : null,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (imageUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    imageUrl,
                                    width: 200,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if (text != null && text.isNotEmpty)
                              Text(
                                text,
                                style: const TextStyle(fontSize: 20),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library, size: 36, color: Colors.blueAccent),
                  onPressed: _pickAndUploadImage,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(fontSize: 20),
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Введите сообщение...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF90EE90),
                  radius: 26,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black87),
                    onPressed: () => _sendMessage(text: _messageController.text),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
