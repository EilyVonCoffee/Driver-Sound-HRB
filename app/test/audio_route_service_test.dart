import 'package:flutter_test/flutter_test.dart';
import 'package:iem_driver/services/audio_route_service.dart';

void main() {
  test('Bluetooth route exposes stable identity and TWS presentation', () {
    final route = AudioRoute.fromJson({
      'id': '7',
      'kind': 'bluetooth',
      'name': 'Studio TWS',
      'bluetoothMac': 'AA:BB:CC:DD:EE:FF',
    });

    expect(route.deviceLabel, 'TWS');
    expect(route.profileKey, 'bluetooth:aa:bb:cc:dd:ee:ff');
    expect(route.matchingProfileKeys, contains('bluetooth:studio tws'));
  });

  test(
      'snapshot does not guess the active route when the OS has not reported it',
      () {
    final snapshot = AudioRouteSnapshot.fromJson({
      'availableOutputs': [
        {'id': 'speaker', 'kind': 'other', 'name': 'Built-in speaker'},
        {
          'id': 'dac',
          'kind': 'usb',
          'name': 'USB Audio DAC',
          'vendorId': 1234,
          'productId': 5678
        },
      ],
    });

    expect(snapshot.activeRoute, isNull);
    expect(snapshot.detectedRoute?.deviceLabel, 'DAC');
    expect(snapshot.detectedRoute?.profileKey, 'usb:1234:5678');
  });

  test('snapshot resolves only the endpoint reported as active', () {
    final snapshot = AudioRouteSnapshot.fromJson({
      'availableOutputs': [
        {'id': 'usb', 'kind': 'usb', 'name': 'USB Audio DAC'},
        {'id': 'jack', 'kind': 'jack', 'name': 'Headphones'},
      ],
      'activeOutputId': 'jack',
    });

    expect(snapshot.activeRoute?.id, 'jack');
  });
}
