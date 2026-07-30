class ServerConfig {
  const ServerConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;

  String get normalizedBaseUrl =>
      baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
}
