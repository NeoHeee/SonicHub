class ServerConfig {
  const ServerConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;

  static String normalizeBaseUrl(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').replaceFirst(RegExp(r'/+$'), '');

  String get normalizedBaseUrl => normalizeBaseUrl(baseUrl);
}
