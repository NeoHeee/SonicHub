import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_config.dart';

class ConfigStore {
  ConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> save(ServerConfig config) async {
    await Future.wait([
      _storage.write(key: 'songloft_base_url', value: config.normalizedBaseUrl),
      _storage.write(key: 'songloft_username', value: config.username),
      _storage.write(key: 'songloft_password', value: config.password),
    ]);
  }

  Future<void> saveSelectedDevice(String accountId, String deviceId) async {
    await Future.wait([
      _storage.write(key: 'selected_device_account_id', value: accountId),
      _storage.write(key: 'selected_device_id', value: deviceId),
    ]);
  }

  Future<({String accountId, String deviceId})?> loadSelectedDevice() async {
    final values = await Future.wait([
      _storage.read(key: 'selected_device_account_id'),
      _storage.read(key: 'selected_device_id'),
    ]);
    if (values.any((value) => value == null || value.isEmpty)) return null;
    return (accountId: values[0]!, deviceId: values[1]!);
  }

  Future<ServerConfig?> load() async {
    final values = await Future.wait([
      _storage.read(key: 'songloft_base_url'),
      _storage.read(key: 'songloft_username'),
      _storage.read(key: 'songloft_password'),
    ]);
    if (values.any((value) => value == null || value.isEmpty)) return null;
    return ServerConfig(
      baseUrl: values[0]!,
      username: values[1]!,
      password: values[2]!,
    );
  }
}
