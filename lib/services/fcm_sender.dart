import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class FcmSender {
  static const _b64 = "ew0KICAidHlwZSI6ICJzZXJ2aWNlX2FjY291bnQiLA0KICAicHJvamVjdF9pZCI6ICJidWJ1bWVzIiwNCiAgInByaXZhdGVfa2V5X2lkIjogIjFjMzVlYTliZjI5NjZhZmFlYTYwNzRmMDEyNTEzOTUwMzJkZmNjZDUiLA0KICAicHJpdmF0ZV9rZXkiOiAiLS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tXG5NSZUV2QUlCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktZd2dnU2lBZ0VBQW9JQkFRREVaRkNoQXU4bVRzZTlcbkZ5M1pGcEErNzNOY1A4dWgvcU56bG04UkIxUzI1ZG5JOXpaZU1QSlM3ZVg2UVF5Q1d1SE13bmFpby9NSlVZTlpcbnhQdXFWNk14L0JmZjRBajFqM0REczBRS1dQVEVVdGM1NkI1UFF3MXpRaEJqUnVMM2xTcU41ZE5pcTFsZGszU1ZcbktrQmZKL3RSK3RxM250d3NLeVE1OXhBQmNKeFZEMURrdlFlTXU2aTE3VlBKcENCdzNlOEcrZGx2MGVHQXFqVGRcbjVrcGV4ejhvMUxmMjROWnd4Mmp1OUJMbkdYR1NFT00zdkdnZmx4VXpmM2JQMWdrUVBxaG5uUUtWMlJmMERuMEdcbjlGRVBGZ1VjMllNaW13ZlNKbU1qb2xMdWN3ZlFIa2VwWWk4TFZxcXZqTko2c2gwSVpTN3BWbU5QNGY5QUxKT1Rcbk5EcUs2UDA1QWdNQkFBRUNnZ0VBQUwyT3dIVUtPMmo3TTRZZkZrWk9tV1hFR3Q0SDJoY2dnQkZPQ2MyV3AxNmtcbjNlWWJ3eFVuSFIrQW1HMlNwTlduTEFIQVE0VUJUR01UcStIMTZraTljcUxBS2pLN2hTYzJmUUtZV25XaVdzOGpcbjBSTjA2N1FQY2dSc0xXVXJqS24rSDRLTm0yNkk2TkZFeTJiTkMvK1BzQnk1MzU4Uy82RlpIbGpzN2trSHlnM3Ncbk1GZ2ZPK1E5Tm9ucE5zTENjZWdqNWNrMExyUkM3Sit2WGNwZllIbTRqSlppdmNEQ3NDanc4bm13bk1jOER4YWpcbmNDZ0FXM2NLaGJpbDY0OXVtTmJFSFNsdW8vOGFuc0ZQdklpT083d0J2S3piR2gvMFFNdnFEQVdOeTR2SHBGdXJcbmxkVldSa2N6TXMrT2d6Q1VCNm9LN1libHdPWUJvdkFBZ0lPeFNONC9VUUtCZ1FEL2FwQkdDNG5JTmRUaUphQ1RcbjFGMllFZFNwU2xvK1dsU1JKR1M1bkp4RmJjUEdLaGQ1dGlUeDFCaVhSZDFKVFZGVUowNDJOeHh6dzFjTnFrY0NcbnFJUDNheElLZ0puZ0luVnpnQ1ovS0F0Q2I5WWMzNENrQkQ5a1VaNjBraFU4cHowMG5ReURwWlJkeFpRUUptaFlcbk1sN3A5YjJvNFZXb04vQ1g2RnFJNFNGbjdRS0JnUURFMXpmTXlkSERMY1pQZnRlNVR5M09xL21QS1poOEdMcGtcbllRWE91NXFMeWVLR1p0VnZ0UE5RTVNOZk9Kc01wc3R5SHExT0kxRlpwNjQ3MXFiOHB2UXhZY0ZrbnNNTFJGOXlcbmVaLzdpWE9BL3JDbUJlc3Q1SVdDbUp0ZHJYZzlZQ2dIRktkMFBxL3loVlhFSzdDbTFmTUIyNDNVcEpKK3poanhcbm5GZDFoY0ZvL1FLQmdCNzB4RzJvNGxjZ3B4K05uZXVzMW5jaTJocDJoMzk5SlRpK0ozTVRseUVYRDU1SjViUjdcbnJmaWRVeW1xYndwK1UzZ1dsM1Vjc3RjWStza09OVE1PUjBvOGNPQlMrOU5kZWN5NDRIR1M0ZUo0ZVlQZ1Z0QUtcbkw4Q3gzOEZVM3p3TnJPNWVobkRDTmJ3endTRU8vOW0rU0UweloydFhJRWNDa253VmFSUGJJQ210MUFvR0FmUFg0XG5LWnp4K290anV2SFdkNERwbnF1VW1hc1piNmF2SmF4bWFIQzIwd21PTWk2MFR0ODhHK3VsL2Z4TWlrS1ZJMVNRXG5SdXVxNkZUSUNwcmhsY0ZUZ3NvQllTUmN4QmxhMHF5ZHdLem8wN3BjWUhtZmJKb0htL25Qb0MvUkJuMjF5NUQwXG5JWnJ1VGZNUm1LRDMyMkkxakRkYW1lVUVUMVg5aGR6dnRONytBdTBDZ1lBWVphVXAnNFQzemVnWVFZYU45U2JkaFxuYzVVRGpiME5UdlFhUHRXeFNobWJoNktDUVpIR0UzSTJrcGEwazNoYnMvcTNURXFEc0E4M2tsTDZabEZhanl4VVxuOHBSU2FyWk9sNWxxbit0a0ZSWGtOUVNNdW51cTdIV1BKOEs0RHcxVnJxZWpiemxmR0NhSERkQkpOZWlQS3YrRlxueDZDZHMvbUFwMXpEN0k4V2ZPRHRHUT09XG4tLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tXG4iLA0KICAiY2xpZW50X2VtYWlsIjogImZpcmViYXNlLWFkbWluc2RrLWZic3ZjQGJ1YnVtZXMuaWFtLmdzZXJ2aWNlYWNjb3VudC5jb20iLA0KICAiY2xpZW50X2lkIjogIjEwNDEzOTgxMjM5ODY1Mjk3NDQ0MCIsDQogICJhdXRoX3VyaSI6ICJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20vby9vYXV0aDIvYXV0aCIsDQogICJ0b2tlbl91cmkiOiAiaHR0cHM6Ly9vYXV0aDIuZ29vZ2xlYXBpcy5jb20vdG9rZW4iLA0KICAiYXV0aF9wcm92aWRlcl94NTA5X2NlcnRfdXJsIjogImh0dHBzOi8vd3d3Lmdvb2dsZWFwaXMuY29tL29hdXRoMi92MS9jZXJ0cyIsDQogICJjbGllbnRfeDUwOV9jZXJ0X3VybCI6ICJodHRwczovL3d3dy5nb29nbGVhcGlzLmNvbS9yb2JvdC92MS9tZXRhZGF0YS94NTA5L2ZpcmViYXNlLWFkbWluc2RrLWZic3ZjJTQwYnVidW1lcy5pYW0uZ3NlcnZpY2VhY2NvdW50LmNvbSIsDQogICJ1bml2ZXJzZV9kb21haW4iOiAiZ29vZ2xlYXBpcy5jb20iDQp9";

  static Future<String> _getAccessToken() async {
    final decodedJson = utf8.decode(base64Decode(_b64));
    final credentials = ServiceAccountCredentials.fromJson(decodedJson);
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client = await clientViaServiceAccount(credentials, scopes);
    final token = client.credentials.accessToken.data;
    client.close();
    return token;
  }

  static Future<void> sendCallNotification({
    required String targetToken,
    required String callerName,
    required String callId,
    required bool isVideo,
  }) async {
    try {
      final token = await _getAccessToken();
      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/bubumes/messages:send');

      final payload = {
        'message': {
          'token': targetToken,
          'notification': {
            'title': 'Входящий звонок',
            'body': 'Вам звонит $callerName',
          },
          'data': {
            'type': 'call',
            'call_id': callId,
            'caller_name': callerName,
            'is_video': isVideo.toString(),
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'calls_channel',
              'sound': 'default'
            }
          }
        }
      };

      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      print('Ошибка при отправке FCM пуша: \$e');
    }
  }
}
