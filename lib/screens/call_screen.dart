import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallScreen extends StatefulWidget {
  final String meetingUrl;
  final bool isVideoCall;
  final String? callId;

  const CallScreen({
    super.key,
    required this.meetingUrl,
    required this.isVideoCall,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final GlobalKey webViewKey = GlobalKey();
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _ensurePermissions();
  }

  Future<void> _ensurePermissions() async {
    final permissions = [Permission.microphone];
    if (widget.isVideoCall) permissions.add(Permission.camera);
    await permissions.request();
  }

  @override
  void dispose() {
    _endCallInDatabase();
    super.dispose();
  }

  Future<void> _endCallInDatabase() async {
    if (widget.callId != null) {
      try {
        await _supabase.from('calls').update({'status': 'ended'}).eq('id', widget.callId!);
      } catch (e) {
        print('Ошибка при завершении звонка: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVideoCall ? 'Видеозвонок' : 'Звонок'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: InAppWebView(
          key: webViewKey,
          initialUrlRequest: URLRequest(url: WebUri(widget.meetingUrl)),
          initialSettings: InAppWebViewSettings(
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            iframeAllow: "camera; microphone",
            iframeAllowFullscreen: true,
            javaScriptEnabled: true,
            userAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36",
          ),
          androidOnPermissionRequest: (controller, origin, resources) async {
            return PermissionRequestResponse(
              resources: resources,
              action: PermissionRequestResponseAction.GRANT,
            );
          },
        ),
      ),
    );
  }
}
