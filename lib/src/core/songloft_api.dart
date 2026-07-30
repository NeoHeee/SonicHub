import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'server_config.dart';

class SongloftApiException implements Exception {
  const SongloftApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SongloftApi {
  SongloftApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final ServerConfig config;
  final http.Client _client;
  String? _accessToken;

  static const _apiPrefix = '/api/v1';
  static const _miotPrefix = '$_apiPrefix/jsplugin/miot';

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${config.normalizedBaseUrl}$path')
          .replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<void> login() async {
    final response = await _client
        .post(
          _uri('$_apiPrefix/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': config.username,
            'password': config.password,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decode(response);
    final token = body['access_token'] ??
        body['token'] ??
        (body['data'] is Map ? body['data']['access_token'] : null);
    if (token == null || token.toString().isEmpty) {
      throw const SongloftApiException('登录成功，但服务端未返回访问令牌');
    }
    _accessToken = token.toString();
  }

  Future<void> testConnection() async {
    final response = await _client
        .get(_uri('$_apiPrefix/health'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SongloftApiException('服务连接失败（HTTP ${response.statusCode}）');
    }
    await login();
  }

  Future<List<SpeakerDevice>> getDevices() async {
    final body = await _getMiot('/mina/devices');
    final groups = body['data'] as List<dynamic>? ?? const [];
    return [
      for (final rawGroup in groups)
        if (rawGroup is Map<String, dynamic>)
          for (final rawDevice in rawGroup['devices'] as List<dynamic>? ?? const [])
            if (rawDevice is Map<String, dynamic>)
              SpeakerDevice.fromJson(
                rawDevice,
                '${rawGroup['account_id'] ?? ''}',
              ),
    ];
  }

  Future<List<MediaItem>> searchSongs(String keyword) async {
    await _ensureLogin();
    final response = await _client.get(
      _uri('$_apiPrefix/songs', {
        'keyword': keyword.trim(),
        'limit': '50',
        'offset': '0',
      }),
      headers: _headers,
    );
    final body = _decode(response);
    final songs = body['songs'] as List<dynamic>? ?? const [];
    return [
      for (final raw in songs)
        if (raw is Map<String, dynamic>) MediaItem.fromJson(raw),
    ];
  }

  Future<List<PlaylistSummary>> getPlaylists() async {
    final body = await _getMiot('/playlists');
    final items = body['data'] as List<dynamic>? ?? const [];
    return [
      for (final raw in items)
        if (raw is Map<String, dynamic>) PlaylistSummary.fromJson(raw),
    ];
  }

  Future<List<MediaItem>> getPlaylistSongs(int playlistId) async {
    final body = await _getMiot('/playlists/$playlistId/songs');
    final items = body['data'] as List<dynamic>? ?? const [];
    return [
      for (final raw in items)
        if (raw is Map<String, dynamic>) MediaItem.fromJson(raw),
    ];
  }

  Future<void> playPlaylist(
    SpeakerDevice device,
    int playlistId, {
    int startIndex = 0,
    int? songId,
  }) =>
      _postMiot('/player/play', device, {
        'playlist_id': playlistId,
        'start_index': startIndex,
        'play_mode': 'order',
        if (songId != null) 'song_id': songId,
      });

  Future<void> previous(SpeakerDevice device) =>
      _postMiot('/player/previous', device);

  Future<void> next(SpeakerDevice device) =>
      _postMiot('/player/next', device);

  Future<void> togglePlayback(SpeakerDevice device) =>
      _postMiot('/player/toggle', device);

  Future<void> seek(SpeakerDevice device, double position) =>
      _postMiot('/player/seek', device, {
        'position': position.clamp(0, 99999999),
      });

  Future<void> playUrl(SpeakerDevice device, String url) =>
      _postMiot('/mina/play-url', device, {'url': url});

  Future<void> pause(SpeakerDevice device) =>
      _postMiot('/mina/pause', device);

  Future<void> resume(SpeakerDevice device) =>
      _postMiot('/mina/resume', device);

  Future<void> stop(SpeakerDevice device) =>
      _postMiot('/mina/stop', device);

  Future<void> setVolume(SpeakerDevice device, int volume) =>
      _postMiot('/mina/volume', device, {'volume': volume.clamp(0, 100)});

  Future<DeviceStatus> getStatus(SpeakerDevice device) async {
    try {
      final body = await _getMiot('/player/status', {
        'account_id': device.accountId,
        'device_id': device.id,
      });
      return DeviceStatus.fromJson(
        (body['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    } on SongloftApiException {
      final body = await _getMiot('/mina/status', {
        'account_id': device.accountId,
        'device_id': device.id,
      });
      return DeviceStatus.fromJson(
        (body['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    }
  }

  Future<Map<String, dynamic>> _getMiot(
    String path, [
    Map<String, String>? query,
  ]) async {
    await _ensureLogin();
    final response = await _client.get(
      _uri('$_miotPrefix$path', query),
      headers: _headers,
    );
    final body = _decode(response);
    _ensurePluginSuccess(body);
    return body;
  }

  Future<void> _postMiot(
    String path,
    SpeakerDevice device, [
    Map<String, dynamic> extra = const {},
  ]) async {
    await _ensureLogin();
    final response = await _client.post(
      _uri('$_miotPrefix$path'),
      headers: _headers,
      body: jsonEncode({
        'account_id': device.accountId,
        'device_id': device.id,
        ...extra,
      }),
    );
    _ensurePluginSuccess(_decode(response));
  }

  Future<void> _ensureLogin() async {
    if (_accessToken == null) await login();
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 401) {
      _accessToken = null;
      throw const SongloftApiException('登录已失效，请重新连接');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SongloftApiException('请求失败（HTTP ${response.statusCode}）');
    }
    try {
      return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      throw const SongloftApiException('服务端返回了无法识别的数据');
    }
  }

  void _ensurePluginSuccess(Map<String, dynamic> body) {
    if (body['success'] != true) {
      throw SongloftApiException('${body['error'] ?? 'MIoT 插件请求失败'}');
    }
  }
}
