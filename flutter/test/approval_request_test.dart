import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/local_web_server_service.dart';

/// Defensive tests for approval-request IDs. Pure statics — no server started.
void main() {
  group('newRequestId', () {
    test('has the req_ prefix and is unique across many mints', () {
      final seen = <String>{};
      for (var i = 0; i < 1000; i++) {
        final id = LocalWebServerService.newRequestId(seen);
        expect(id.startsWith('req_'), isTrue);
        expect(seen.contains(id), isFalse, reason: 'collision at iteration $i');
        seen.add(id);
      }
    });

    test('never returns a taken ID', () {
      final first = LocalWebServerService.newRequestId({});
      final second = LocalWebServerService.newRequestId({first});
      expect(second, isNot(first));
    });
  });
}
