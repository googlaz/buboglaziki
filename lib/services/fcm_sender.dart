import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class FcmSender {
  static const _b64 = "ewogICJ0eXBlIjogInNlcnZpY2VfYWNjb3VudCIsCiAgInByb2plY3RfaWQiOiAiYnVidW1lcyIsCiAgInByaXZhdGVfa2V5X2lkIjogIjFjMzVlYTliZjI5NjZhZmFlYTYwNzRmMDEyNTEzOTUwMzJkZmNjZDUiLAogICJwcml2YXRlX2tleSI6ICItLS0tLUJFR0lOIFBSSVZBVEUgS0VZLS0tLS1cbk1JSUV2QUlCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktZd2dnU2lBZ0VBQW9JQkFRREVaRkNoQXU4bVRzZTlcbkZ5M1pGcEErNzNOY1A4dWgvcU56bG04UkIxUzI1ZG5JOXpaZU1QSlM3ZVg2UVF5Q1d1SE13bmFpby9NSlVZTkpcbnhQdXFWNk14L0JmZjRBajFqM0REczBRS1dQVEVVdGM1NkI1UFF3MXpRaEJqUnVMM2xTcU41ZE5pcTFsZGszU1ZcbktrQmZKL3RSK3RxM250d3NLelE1OXhBQmNKeFZEMURrdlFlTXU2aTE3VlBKcENCdzNlOEcrZGx2MGVHQXFqVGRcbjVrcGV4ejhvMUxmMjROWnd4Mmp1OUJMbkdYR1NFT00zdkdnZmx4VXpmM2JQMWdrUVBxaG5uUUtWMlJmMERuMEdcbjlGRVBGZ1VjMllNaW13ZlNKbE1qb2xMdWN3ZlFIa2VwWWk4TFZxcXZqTko2c2gwSVpTN3BWbU5QNGY5QUxKT1Rcbk5EcUs2UDA1QWdNQkFBRUNnZ0VBQUwyT3dIVUtPMmo3TTRZZkZrWk9tV1hFR3Q0SDJoY2dnQkZPQ2MyV3AxNmtcbjNlWWJ3eFVuSFIrQW1HMlNwTlduTEFIQVE0VUJUR01UcStIMTZraTljcUxBS2pLN2hTYzJmUUtZV25XaVdzOGpcbjBSTjA2N1FQY2dSc0xXVXJqS24rSDRLTm0yNkk2TkZFeTJiTkMvK1BzQnk1MzU4Uy82RlpIbGpzN2trSHlnM3Ncbm1GZ2ZPK1E5Tm9ucE5zTENjZWdqNWNrMExyUkM3Sit2WGNwZllIbTRqSlppdmNEQ3NDanc4bm13bk1jOER4YWpcbmNDZ0FXM2NLaGJpbDY0OXVtTmJFSFNsdW8vOGFuc0ZQdklpT083d0J2S3piR2gvMFFNdnFEQVdOeTR2SHBGdXJcbmxkVldSa2N6TXMrT2d6Q1VCNm9LN1libHdPWUJvdkFBZ0lPeFNSNC9VUUtCZ1FEL2FwQkdDNG5JTmRUaUphQ1RcbjFGMllFZFNwU2xvK1dsU1JKR1M1bkp4RmJjUEdLaGQ1dGlUeDFCaVhSZDFKVFZGVUowNDJOeHh6dzFjTnFrY0NcbnFJSDNheElLZ0puZ0luVnpnQ1ovS0F0Q2I5WWMzNENrQkQ5a1VaNjBraFU4cHowMG5ReURwWlJkeFpRUUptaFlcbk1sN3A5YjJvNFZXb04vQ1g2RnFJNFNGbjdRS0JnUURFMXpmTXlkSERMY1pQZnRlNVR5M09xL21QS1poOEdMcGtcbllRWE91NXFMeWVLR1p0VnZ0UE5RTVNOZk9Kc01wc3R5SHExT0kxRlpwNjQ3MXFiOHB2UXhZY0ZrbnNNTFJGOXlcbmVaLzdpWE9BL3JDbUJlc3Q1SVdDbUp0ZHJYZzlZQ2dIRktkMFBxL3loVlhFSzdDbTFmTUIyNDNVcEpKK3poanhcbm5GZDFoY0ZvL1FLQmdCNzB4RzJvNGxjZ3B4K05uZXVzMW5jaTJocDJoMzk5SlRpK0ozTVRseUVYRDU1SjViUjdccmZpZFV5bXFid3ArVTNnV2wzVWNzdGNZK3NrT05UTU9SMG84Y09CUys5TmRlY3k0NEhHUzRlSjRlWVBnVnRBS1xuTDhDeDM4RlUzendOck81ZWhuRENOYnd6d1NFLzltK1NFMHpaMnRYSUVjQ2tud1ZhUlBiSUNtdDFBb0dBZlBYNFxLWnp4K290anV2SFdkNERwbnF1VW1hc1piNmF2SmF4bWFIQzIwd21PTWk2MFR0ODhHK3VsL2Z4TWlrS1ZJMVNRXG5SdXVxNkZUSUNwcmhsY0ZUZ3NvQllTUmN4QmxhMHF5ZHdLem8wN3BjWUhtZmJKb0htL25Qb0MvUkJuMjF5NUQwXG5JWnJ1VGZNUm1LRDMyMkkxakRkYW1lVUVUMVg5aGR6dnRONytBdTBDZ1lBWVphVXA0VDN6ZWdZUVlhTjlTYmRoXG5jNVVEamIwTlR2UWFQdFd4U2htYkg2S0NRWkhHRTNJMmtwYTBrM2hicy9xM1RFcURzQTgza2xMNlpsRmFqeXhVXG44cFJTYXJaT2w1bHFuK3RrRlJYa05RU011bnVxN0hXUEo4SzREdzFWcnFlamJ6bGZHQ2FIRGRCSk5laVBLditGXG54NkNkcy9tQXAxekQ3SThXZk9EdEdRPT1cbi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS1cbiIsCiAgImNsaWVudF9lbWFpbCI6ICJmaXJlYmFzZS1hZG1pbnNkay1mYnN2Y0BidWJ1bWVzLmlhbS5nc2VydmljZWFjY291bnQuY29tIiwKICAiY2xpZW50X2lkIjogIjEwNDEzOTgxMjM5ODY1Mjk3NDQ0MCIsCiAgImF1dGhfdXJpIjogImh0dHBzOi8vYWNjb3VudHMuZ29vZ2xlLmNvbS9vL29hdXRoMi9hdXRoIiwKICAidG9rZW5fdXJpIjogImh0dHBzOi8vb2F1dGgyLmdvb2dsZWFwaXMuY29tL3Rva2VuIiwKICAiYXV0aF9wcm92aWRlcl94NTA5X2NlcnRfdXJsIjogImh0dHBzOi8vd3d3Lmdvb2dsZWFwaXMuY29tL29hdXRoMi92MS9jZXJ0cyIsCiAgImNsaWVudF94NTA5X2NlcnRfdXJsIjogImh0dHBzOi8vd3d3Lmdvb2dsZWFwaXMuY29tL3JvYm90L3YxL21ldGFkYXRhL3g1MDkvZmlyZWJhc2UtYWRtaW5zZGstZmJzdmMlNDBidWJ1bWVzLmlhbS5nc2VydmljZWFjY291bnQuY29tIiwKICAidW5pdmVyc2VfZG9tYWluIjogImdvb2dsZWFwaXMuY29tIgp9Cg==";

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
