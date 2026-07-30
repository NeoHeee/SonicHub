class SpeakerDevice {
  const SpeakerDevice({
    required this.accountId,
    required this.id,
    required this.name,
    this.model,
  });

  final String accountId;
  final String id;
  final String name;
  final String? model;

  factory SpeakerDevice.fromJson(
    Map<String, dynamic> json,
    String accountId,
  ) {
    return SpeakerDevice(
      accountId: accountId,
      id: '${json['deviceID'] ?? json['device_id'] ?? json['id'] ?? ''}',
      name: '${json['name'] ?? json['alias'] ?? '未命名音箱'}',
      model: json['model']?.toString(),
    );
  }
}

class DeviceStatus {
  const DeviceStatus({
    required this.state,
    required this.volume,
    required this.position,
  });

  final String state;
  final int? volume;
  final double position;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      state: '${json['state'] ?? 'unknown'}',
      volume: (json['volume'] as num?)?.toInt(),
      position: (json['position'] as num?)?.toDouble() ?? 0,
    );
  }
}
