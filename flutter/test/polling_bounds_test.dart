import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/polling_service.dart';

/// Defensive tests for polling bounds. Pure statics — no storage touched.
void main() {
  group('clampInterval', () {
    test('bounds', () {
      expect(PollingService.clampInterval(5000), 5000);
      expect(PollingService.clampInterval(0), 1000);
      expect(PollingService.clampInterval(-100), 1000);
      expect(PollingService.clampInterval(999999999), 86400000);
    });
  });

  group('clampThreshold', () {
    test('falls back outside range', () {
      expect(PollingService.clampThreshold(300000, 300000), 300000);
      expect(PollingService.clampThreshold(0, 300000), 0);
      expect(PollingService.clampThreshold(-1, 300000), 300000);
      expect(PollingService.clampThreshold(604800001, 300000), 300000);
      expect(PollingService.clampThreshold(604800000, 300000), 604800000);
    });
  });
}
