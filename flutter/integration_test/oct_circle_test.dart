import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

/// E2E: the exact circle URL from the field report must be servable.
///
/// Hits the live devnet node (same call the in-app browser makes) and
/// asserts the asset exists with a renderable content type and body.
/// Runs on the emulator nightly + on demand; needs internet.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const circleId = 'oct99BWHFpV5r54DXKc2FhsBmZEaS6Q8zvCQrHRgXUcK4Fk';
  const rpcUrl = 'https://devnet.octrascan.io/rpc';

  testWidgets('oct:// circle page is servable', (tester) async {
    final resp = await http
        .post(
          Uri.parse(rpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'circle_asset',
            'params': [circleId, '/index.html'],
            'id': 1,
          }),
        )
        .timeout(const Duration(seconds: 30));

    expect(resp.statusCode, 200);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    expect(json.containsKey('error'), isFalse,
        reason: 'node error: ${resp.body}');
    final result = json['result'] as Map<String, dynamic>;
    final contentType =
        (result['content_type']?.toString() ?? '').split(';').first.trim();
    expect(contentType, startsWith('text/'),
        reason: 'index page must be text, got "$contentType"');
    final body = result['body_b64']?.toString() ?? '';
    expect(body.isNotEmpty, isTrue, reason: 'empty asset body');
    expect(base64Decode(body).isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
