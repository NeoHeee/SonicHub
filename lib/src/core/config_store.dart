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
