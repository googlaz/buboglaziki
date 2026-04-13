import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'login_code_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
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
                        leading: CircleAvatar(
                          radius: 35,
                          backgroundColor: const Color(0xFF90EE90),
                          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 30) : null,
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 20)),
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
