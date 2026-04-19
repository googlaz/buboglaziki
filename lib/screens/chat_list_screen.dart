import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'login_code_screen.dart';
import 'incoming_call_screen.dart';
import 'profile_screen.dart';
import '../services/fcm_service.dart';

class ChatListScreen extends StatefulWidget {
  final String currentUserId;
  const ChatListScreen({super.key, required this.currentUserId});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _profiles = [];
  bool _isLoading = true;
  RealtimeChannel? _incomingCallChannel;
  String _currentUserName = 'Семьянин';
  String _currentUserAvatarUrl = '';
  // Защита от двойного открытия экрана входящего звонка
  bool _isShowingIncomingCall = false;

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
    _saveFcmToken();
    _loadCurrentUserName();
    _subscribeToIncomingCalls();
  }

  Future<void> _loadCurrentUserName() async {
    try {
      final res = await _supabase
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', widget.currentUserId)
          .single();
      if (mounted) {
        setState(() {
          _currentUserName = res['display_name'] ?? 'Семьянин';
          _currentUserAvatarUrl = res['avatar_url'] ?? '';
        });
      }
    } catch (_) {}
  }

  /// Подписка на входящие звонки через Supabase Realtime.
  /// Это резервный канал — работает когда приложение открыто,
  /// даже если FCM не доставил уведомление.
  void _subscribeToIncomingCalls() {
    final receiverId = int.tryParse(widget.currentUserId);
    if (receiverId == null) return;

    _incomingCallChannel = _supabase
        .channel('incoming_calls_${widget.currentUserId}')
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
            final status = record['status'];
            if (status != 'ringing') return;
            if (_isShowingIncomingCall) return;

            final callId = record['id']?.toString();
            final callerId = record['caller_id']?.toString();
            if (callId == null || callerId == null) return;

            // Получаем имя звонящего из базы
            String callerName = 'Семьянин';
            try {
              final callerProfile = await _supabase
                  .from('profiles')
                  .select('display_name')
                  .eq('id', int.parse(callerId))
                  .single();
              callerName = callerProfile['display_name'] ?? 'Семьянин';
            } catch (_) {}

            if (!mounted) return;
            _showIncomingCall(callId, callerName, false);
          },
        )
        .subscribe();
  }

  void _showIncomingCall(String callId, String callerName, bool isVideo) {
    if (_isShowingIncomingCall || !mounted) return;
    _isShowingIncomingCall = true;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingCallScreen(
          callId: callId,
          callerName: callerName,
          isVideoCall: isVideo,
          currentUserName: _currentUserName,
        ),
      ),
    ).then((_) {
      _isShowingIncomingCall = false;
    });
  }

  Future<void> _saveFcmToken() async {
    await FcmService.saveTokenToDb(widget.currentUserId);
    FcmService.listenTokenRefresh(widget.currentUserId);
  }

  Future<void> _fetchProfiles() async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .neq('id', widget.currentUserId)
          .timeout(const Duration(seconds: 15));
      setState(() {
        _profiles = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки пользователей: $e')),
        );
      }
    }
  }

  void _openChat(String title, String? targetUserId, bool isGroup) {
    String chatId;
    if (isGroup) {
      chatId = 'family_group';
    } else {
      final ids = [widget.currentUserId, targetUserId!];
      ids.sort();
      chatId = ids.join('_');
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chatId,
          title: title,
          currentUserId: widget.currentUserId,
          otherUserId: isGroup ? null : targetUserId,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_profile_id');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginCodeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _incomingCallChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          // Аватарка текущего пользователя → открыть свой профиль
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    profileId: widget.currentUserId,
                    currentUserId: widget.currentUserId,
                  ),
                ),
              ).then((_) => _loadCurrentUserName());
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                backgroundImage: _currentUserAvatarUrl.isNotEmpty
                    ? NetworkImage(_currentUserAvatarUrl)
                    : null,
                child: _currentUserAvatarUrl.isEmpty
                    ? const Icon(Icons.person, size: 20, color: Colors.white)
                    : null,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Сменить пользователя',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  leading: const CircleAvatar(
                    radius: 35,
                    backgroundColor: Color(0xFFFFB6C1),
                    child: Icon(Icons.family_restroom, size: 35, color: Colors.white),
                  ),
                  title: const Text('Вся семья', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Общий семейный чат', style: TextStyle(fontSize: 16)),
                  onTap: () => _openChat('Вся семья', null, true),
                ),
                const Divider(thickness: 2),
                Expanded(
                  child: ListView.builder(
                    itemCount: _profiles.length,
                    itemBuilder: (context, index) {
                      final profile = _profiles[index];
                      final name = profile['display_name'] ?? 'Без имени';
                      final avatarUrl = profile['avatar_url'] ?? '';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        leading: GestureDetector(
                          // Нажатие на аватарку → профиль
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(
                                  profileId: profile['id'].toString(),
                                  currentUserId: widget.currentUserId,
                                ),
                              ),
                            );
                          },
                          child: CircleAvatar(
                            radius: 35,
                            backgroundColor: const Color(0xFF90EE90),
                            backgroundImage:
                                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl.isEmpty
                                ? const Icon(Icons.person, size: 30)
                                : null,
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 20)),
                        // Нажатие на строку → чат
                        onTap: () => _openChat(name, profile['id'].toString(), false),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
