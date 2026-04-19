import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  /// ID профиля, который смотрим
  final String profileId;

  /// ID текущего вошедшего пользователя
  final String currentUserId;

  const ProfileScreen({
    super.key,
    required this.profileId,
    required this.currentUserId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _bioController = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;

  bool get _isMyProfile => widget.profileId == widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('id, display_name, avatar_url, bio')
          .eq('id', widget.profileId)
          .single();
      setState(() {
        _profile = data;
        _bioController.text = data['bio'] ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки профиля: $e')),
        );
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (!_isMyProfile) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final fileName = 'avatars/${const Uuid().v4()}.$ext';

      await _supabase.storage.from('family-media').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );
      final url = _supabase.storage.from('family-media').getPublicUrl(fileName);

      await _supabase
          .from('profiles')
          .update({'avatar_url': url}).eq('id', widget.profileId);

      setState(() {
        _profile = {...?_profile, 'avatar_url': url};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фото профиля обновлено ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки фото: $e')),
        );
      }
    } finally {
      setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _saveBio() async {
    setState(() => _isSaving = true);
    try {
      await _supabase
          .from('profiles')
          .update({'bio': _bioController.text.trim()}).eq('id', widget.profileId);
      setState(() {
        _profile = {...?_profile, 'bio': _bioController.text.trim()};
        _isEditing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Профиль сохранён ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showFullScreenAvatar(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 80,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_isMyProfile ? 'Мой профиль' : 'Профиль'),
        actions: [
          if (_isMyProfile && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Редактировать',
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isMyProfile && _isEditing)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.check, color: Colors.white),
                    tooltip: 'Сохранить',
                    onPressed: _saveBio,
                  ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Профиль не найден'))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Шапка с аватаркой
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.primaryColor.withOpacity(0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            // Аватарка
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    final url = _profile!['avatar_url'] as String? ?? '';
                                    if (url.isNotEmpty) _showFullScreenAvatar(url);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: _isUploadingAvatar
                                        ? const CircleAvatar(
                                            radius: 60,
                                            backgroundColor: Colors.white24,
                                            child: CircularProgressIndicator(
                                                color: Colors.white),
                                          )
                                        : CircleAvatar(
                                            radius: 60,
                                            backgroundColor: Colors.white24,
                                            backgroundImage: (_profile![
                                                            'avatar_url'] as
                                                        String? ??
                                                    '')
                                                .isNotEmpty
                                                ? NetworkImage(
                                                    _profile!['avatar_url'])
                                                : null,
                                            child: (_profile!['avatar_url']
                                                            as String? ??
                                                        '')
                                                    .isEmpty
                                                ? const Icon(Icons.person,
                                                    size: 60,
                                                    color: Colors.white)
                                                : null,
                                          ),
                                  ),
                                ),
                                // Кнопка смены фото (только для своего профиля)
                                if (_isMyProfile)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: _pickAndUploadAvatar,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.camera_alt,
                                          size: 20,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Имя
                            Text(
                              _profile!['display_name'] ?? 'Семьянин',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Карточка с биографией/статусом
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: AppTheme.primaryColor, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'О себе',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _isEditing
                                    ? TextField(
                                        controller: _bioController,
                                        maxLines: 4,
                                        maxLength: 200,
                                        decoration: InputDecoration(
                                          hintText:
                                              'Напишите что-нибудь о себе...',
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: AppTheme.primaryColor,
                                                width: 2),
                                          ),
                                        ),
                                      )
                                    : Text(
                                        (_profile!['bio'] as String? ?? '')
                                                .isNotEmpty
                                            ? _profile!['bio']
                                            : _isMyProfile
                                                ? 'Нажмите ✏️ чтобы добавить информацию о себе'
                                                : 'Пользователь пока ничего не написал о себе',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: (_profile!['bio'] as String? ??
                                                      '')
                                                  .isEmpty
                                              ? Colors.grey
                                              : Colors.black87,
                                          height: 1.5,
                                          fontStyle: (_profile!['bio'] as String? ??
                                                      '')
                                                  .isEmpty
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}
