import 'package:flutter_test/flutter_test.dart';
import 'package:sonichub/src/core/models.dart';

void main() {
  test('parses MIoT device using upstream field names', () {
    final device = SpeakerDevice.fromJson(
      {
        'deviceID': 'speaker-1',
        'name': '客厅音箱',
        'model': 'LX06',
      },
      'account-1',
    );

    expect(device.accountId, 'account-1');
    expect(device.id, 'speaker-1');
    expect(device.name, '客厅音箱');
    expect(device.model, 'LX06');
  });

  test('parses nullable device status safely', () {
    final status = DeviceStatus.fromJson({
      'state': 'playing',
      'volume': null,
      'position': 12.5,
    });

    expect(status.state, 'playing');
    expect(status.volume, isNull);
    expect(status.position, 12.5);
  });
}
