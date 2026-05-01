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
import '../services/fcm_sender.dart';
import '../theme/app_theme.dart';

// Цвета имён отправителей для группового чата (как в Telegram)
const List<Color> _senderNameColors = [
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFF1E88E5),
  Color(0xFF00897B),
  Color(0xFFF4511E),
  Color(0xFF6D4C41),
];

Color _colorForSender(String senderId) {
  final code = senderId.codeUnits.fold(0, (a, b) => a + b);
  return _senderNameColors[code % _senderNameColors.length];
}

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

  // Кеш: sender_id → display_name
  final Map<String, String> _senderNames = {};

  // Ответ на сообщение
  Map<String, dynamic>? _replyToMessage;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _fetchAllProfiles();
    _subscribeToIncomingCalls();
  }

  Future<void> _fetchAllProfiles() async {
    try {
      final rows = await _supabase.from('profiles').select('id, display_name');
      final map = <String, String>{};
      for (final row in rows as List) {
        final id = row['id']?.toString() ?? '';
        final name = row['display_name']?.toString() ?? 'Семьянин';
        if (id.isNotEmpty) map[id] = name;
      }
      if (mounted) setState(() => _senderNames.addAll(map));
    } catch (_) {}
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
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserName() async {
    try {
      final res = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', widget.currentUserId)
          .single();
      setState(() => _currentUserName = res['display_name']);
    } catch (_) {}
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    if ((text == null || text.trim().isEmpty) && imageUrl == null) return;

    final content = text?.trim();
    _messageController.clear();

    final data = <String, dynamic>{
      'chat_id': widget.chatId,
      'sender_id': widget.currentUserId,
      'content': content,
      'image_url': imageUrl,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    // Если отвечаем на сообщение — сохраняем id + снапшот текста и имени
    if (_replyToMessage != null) {
      data['reply_to_id'] = _replyToMessage!['id']?.toString();
      data['reply_to_content'] = (_replyToMessage!['content'] as String? ?? '').isNotEmpty
          ? _replyToMessage!['content'] as String
          : '📷 Фото';
      final replySenderId = (_replyToMessage!['sender_id'] ?? '').toString();
      data['reply_to_sender_name'] = _senderNames[replySenderId] ?? 'Семьянин';
    }

    await _supabase.from('messages').insert(data);

    // Рассылка пуш-уведомлений
    try {
      if (widget.otherUserId != null) {
        // Личный чат
        final receiverId = int.parse(widget.otherUserId!);
        print('PUSH: отправляю уведомление для receiverId=$receiverId');
        final p = await _supabase.from('profiles').select('fcm_token').eq('id', receiverId).single();
        final token = p['fcm_token'] as String?;
        print('PUSH: токен получателя: ${token != null ? "${token.substring(0, 20)}..." : "NULL"}');
        if (token != null && token.isNotEmpty) {
          await FcmSender.sendMessageNotification(
            targetToken: token,
            senderName: _currentUserName,
            messageText: content ?? '',
            chatId: widget.chatId,
          );
          print('PUSH: уведомление отправлено ✓');
        } else {
          print('PUSH: токен пуст или null — уведомление НЕ отправлено');
        }
      } else {
        // Групповой чат - достаем всех кроме себя
        final profiles = await _supabase.from('profiles').select('fcm_token').neq('id', int.parse(widget.currentUserId));
        print('PUSH: групповой чат, найдено ${(profiles as List).length} получателей');
        for (var row in profiles) {
          final token = row['fcm_token'] as String?;
          if (token != null && token.isNotEmpty) {
            await FcmSender.sendMessageNotification(
              targetToken: token,
              senderName: '$_currentUserName (Вся семья)',
              messageText: content ?? '',
              chatId: widget.chatId,
            );
            print('PUSH: групповое уведомление отправлено ✓');
          }
        }
      }
    } catch (e) {
      print('PUSH ERROR: ошибка при рассылке уведомлений: $e');
    }

    if (mounted) setState(() => _replyToMessage = null);
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
      final imageUrl =
          _supabase.storage.from('family-media').getPublicUrl(fileName);
      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки фото: $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Контекстное меню при долгом нажатии
  // -------------------------------------------------------------------------
  void _showMessageMenu(
      BuildContext context, Map<String, dynamic> msg, bool isMe) {
    final text = msg['content'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Превью сообщения
            if (text.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  text.length > 80 ? '${text.substring(0, 80)}...' : text,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 13, height: 1.3),
                  textAlign: TextAlign.center,
                ),
              ),
            const Divider(height: 1),
            // Ответить
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.blue),
              title: const Text('Ответить'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyToMessage = msg);
              },
            ),
            // Переслать
            ListTile(
              leading: const Icon(Icons.forward, color: Colors.green),
              title: const Text('Переслать'),
              onTap: () {
                Navigator.pop(context);
                _showForwardDialog(msg);
              },
            ),
            // Удалить
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(msg, isMe);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Диалог удаления
  // -------------------------------------------------------------------------
  void _showDeleteDialog(Map<String, dynamic> msg, bool isMe) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Выберите способ удаления:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteForMe(msg);
            },
            child: const Text('Удалить у меня'),
          ),
          if (isMe)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteForAll(msg);
              },
              child: const Text('Удалить у всех',
                  style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  // Удалить у всех — полное удаление из БД (только своё сообщение)
  Future<void> _deleteForAll(Map<String, dynamic> msg) async {
    try {
      await _supabase
          .from('messages')
          .delete()
          .eq('id', msg['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    }
  }

  // Удалить у меня — помечаем в массиве deleted_for через RPC
  Future<void> _deleteForMe(Map<String, dynamic> msg) async {
    try {
      final msgId = msg['id'];
      // Получаем свежие данные о сообщении из БД
      final fresh = await _supabase
          .from('messages')
          .select('deleted_for')
          .eq('id', msgId)
          .single();

      final currentDeletedFor =
          ((fresh['deleted_for'] as List?)?.cast<String>() ?? <String>[]);

      if (!currentDeletedFor.contains(widget.currentUserId)) {
        currentDeletedFor.add(widget.currentUserId);
      }

      await _supabase
          .from('messages')
          .update({'deleted_for': currentDeletedFor})
          .eq('id', msgId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Диалог пересылки
  // -------------------------------------------------------------------------
  void _showForwardDialog(Map<String, dynamic> msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Переслать в чат'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _supabase
                .from('profiles')
                .select('id, display_name')
                .neq('id', widget.currentUserId),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final profiles = snapshot.data ?? [];
              return ListView.builder(
                shrinkWrap: true,
                itemCount: profiles.length,
                itemBuilder: (ctx, i) {
                  final p = profiles[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(p['display_name'] ?? 'Семьянин'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _forwardMessage(msg, p['id'].toString());
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Future<void> _forwardMessage(
      Map<String, dynamic> msg, String targetUserId) async {
    try {
      // Формируем chatId для личного чата с получателем
      final ids = [widget.currentUserId, targetUserId]..sort();
      final targetChatId = ids.join('_');

      // Определяем оригинального отправителя
      final originalSenderId = (msg['sender_id'] ?? '').toString();
      final originalSenderName = _senderNames[originalSenderId] ?? _currentUserName;

      await _supabase.from('messages').insert({
        'chat_id': targetChatId,
        'sender_id': widget.currentUserId,
        'content': msg['content'],
        'image_url': msg['image_url'],
        'forwarded_from_name': originalSenderName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сообщение переслано ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка пересылки: $e')),
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
          const SnackBar(
              content: Text('Собеседник ещё не открывал приложение.')),
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
    final isGroupChat = widget.otherUserId == null;

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

                final allMessages = snapshot.data ?? [];

                // Фильтруем сообщения удалённые "у меня"
                final messages = allMessages.where((msg) {
                  final deletedFor =
                      (msg['deleted_for'] as List?)?.cast<dynamic>() ?? [];
                  return !deletedFor.contains(widget.currentUserId);
                }).toList();

                return Container(
                  color: AppTheme.chatBackgroundColor,
                  child: ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    itemCount: messages.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final senderId = (msg['sender_id'] ?? '').toString();
                      final isMe = senderId == widget.currentUserId;
                      final text = msg['content'] as String?;
                      final imageUrl = msg['image_url'] as String?;

                      // Время: UTC → локальное время пользователя
                      DateTime timestamp;
                      try {
                        timestamp = msg['created_at'] != null
                            ? DateTime.parse(msg['created_at'].toString())
                                .toLocal()
                            : DateTime.now();
                      } catch (_) {
                        timestamp = DateTime.now();
                      }
                      final timeStr =
                          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

                      final senderName = isGroupChat && !isMe
                          ? (_senderNames[senderId] ?? 'Семьянин')
                          : null;

                      return GestureDetector(
                        onLongPress: () =>
                            _showMessageMenu(context, msg, isMe),
                        child: _MessageBubble(
                          isMe: isMe,
                          text: text,
                          imageUrl: imageUrl,
                          timeStr: timeStr,
                          senderName: senderName,
                          senderId: senderId,
                          replyToContent: msg['reply_to_content'] as String?,
                          replyToSenderName: msg['reply_to_sender_name'] as String?,
                          forwardedFromName: msg['forwarded_from_name'] as String?,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Плашка ответа — показывается когда выбрано сообщение для ответа
        if (_replyToMessage != null)
          Container(
            color: const Color(0xFFF0F0F0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _senderNames[
                                (_replyToMessage!['sender_id'] ?? '')
                                    .toString()] ??
                            'Сообщение',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      Text(
                        (_replyToMessage!['content'] as String? ?? '')
                            .replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      setState(() => _replyToMessage = null),
                ),
              ],
            ),
          ),
        // Поле ввода
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 4,
                offset: Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.photo_library,
                    size: 28, color: Colors.grey),
                onPressed: _pickAndUploadImage,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(fontSize: 18),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение...',
                      hintStyle: TextStyle(fontSize: 18, color: Colors.grey),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                radius: 24,
                child: IconButton(
                  icon:
                      const Icon(Icons.send, color: Colors.white, size: 22),
                  onPressed: () =>
                      _sendMessage(text: _messageController.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _MessageBubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final String? text;
  final String? imageUrl;
  final String timeStr;
  final String? senderName;
  final String senderId;
  final String? replyToContent;
  final String? replyToSenderName;
  final String? forwardedFromName;

  const _MessageBubble({
    required this.isMe,
    this.text,
    this.imageUrl,
    required this.timeStr,
    required this.senderId,
    this.senderName,
    this.replyToContent,
    this.replyToSenderName,
    this.forwardedFromName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 64 : 8,
        right: isMe ? 8 : 64,
        top: 2,
        bottom: 2,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: isMe
                ? AppTheme.sentMessageColor
                : AppTheme.receivedMessageColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Имя отправителя в группе
                if (senderName != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      senderName!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _colorForSender(senderId),
                        height: 1.2,
                      ),
                    ),
                  ),
                // Плашка «Переслано от ...»
                if (forwardedFromName != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.forward, size: 14, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Переслано от $forwardedFromName',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Цитата при ответе
                if (replyToContent != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: isMe ? const Color(0xFF4CAF50) : Colors.blueAccent,
                          width: 3,
                        ),
                      ),
                      color: Colors.black.withOpacity(0.05),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (replyToSenderName != null)
                          Text(
                            replyToSenderName!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isMe ? const Color(0xFF4CAF50) : Colors.blueAccent,
                            ),
                          ),
                        Text(
                          replyToContent!.length > 60
                              ? '${replyToContent!.substring(0, 60)}...'
                              : replyToContent!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                if (imageUrl != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        8, senderName != null ? 6 : 8, 8, 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl!,
                        width: 220,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return SizedBox(
                            height: 160,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 100,
                          child: Center(
                            child: Icon(Icons.broken_image,
                                size: 40, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    (senderName != null || imageUrl != null) ? 4 : 8,
                    8,
                    6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: (text != null && text!.isNotEmpty)
                            ? Text(
                                text!,
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.35,
                                  color: Color(0xFF111111),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: isMe
                                    ? const Color(0xFF5BAD72)
                                    : AppTheme.timestampColor,
                                height: 1.0,
                              ),
                            ),
                            if (isMe)
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Icon(
                                  Icons.done_all,
                                  size: 13,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
