import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AudiobookshelfConfig {
  const AudiobookshelfConfig({required this.baseUrl, required this.apiKey, this.libraryId = ''});
  final String baseUrl;
  final String apiKey;
  final String libraryId;
  String get normalizedBaseUrl => baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  Map<String, String> get audioHeaders => {
    'Authorization': 'Bearer ${apiKey.trim()}',
  };
  Uri resolveContentUrl(String contentUrl) {
    final value = contentUrl.trim();
    final parsed = Uri.tryParse(value);
    if (parsed == null || value.isEmpty) {
      throw const AudiobookshelfException('音轨缺少播放地址');
    }
    if (parsed.hasScheme) return parsed;
    return Uri.parse('$normalizedBaseUrl/').resolve(value);
  }
  AudiobookshelfConfig copyWith({String? libraryId}) => AudiobookshelfConfig(baseUrl: baseUrl, apiKey: apiKey, libraryId: libraryId ?? this.libraryId);
}

class AudiobookshelfConfigStore {
  AudiobookshelfConfigStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  Future<AudiobookshelfConfig?> load() async {
    final values = await Future.wait([
      _storage.read(key: 'abs_base_url'),
      _storage.read(key: 'abs_api_key'),
      _storage.read(key: 'abs_library_id'),
    ]);
    if (values[0]?.isNotEmpty != true || values[1]?.isNotEmpty != true) return null;
    return AudiobookshelfConfig(baseUrl: values[0]!, apiKey: values[1]!, libraryId: values[2] ?? '');
  }
  Future<void> save(AudiobookshelfConfig config) => Future.wait([
    _storage.write(key: 'abs_base_url', value: config.normalizedBaseUrl),
    _storage.write(key: 'abs_api_key', value: config.apiKey.trim()),
    _storage.write(key: 'abs_library_id', value: config.libraryId),
  ]);
}

class AbsLibrary {
  const AbsLibrary({required this.id, required this.name});
  final String id;
  final String name;
  factory AbsLibrary.fromJson(Map<String, dynamic> json) => AbsLibrary(id: '${json['id'] ?? ''}', name: '${json['name'] ?? '未命名书库'}');
}

class AbsProgress {
  const AbsProgress({required this.currentTime, required this.duration, required this.isFinished, required this.lastUpdate});
  final double currentTime;
  final double duration;
  final bool isFinished;
  final int lastUpdate;
  double get ratio => duration <= 0 ? 0 : (currentTime / duration).clamp(0, 1);
  factory AbsProgress.fromJson(Map<String, dynamic>? json) => AbsProgress(
    currentTime: (json?['currentTime'] as num?)?.toDouble() ?? 0,
    duration: (json?['duration'] as num?)?.toDouble() ?? 0,
    isFinished: json?['isFinished'] == true,
    lastUpdate: (json?['lastUpdate'] as num?)?.toInt() ?? 0,
  );
}

class AbsBook {
  const AbsBook({required this.id, required this.title, required this.author, required this.narrator, required this.duration, required this.progress});
  final String id;
  final String title;
  final String author;
  final String narrator;
  final double duration;
  final AbsProgress progress;
  String get subtitle => [if (author.trim().isNotEmpty) author.trim(), if (narrator.trim().isNotEmpty) '演播 $narrator'].join(' · ');
  factory AbsBook.fromJson(Map<String, dynamic> json) {
    final media = (json['media'] as Map?)?.cast<String, dynamic>() ?? const {};
    final metadata = (media['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawProgress = json['userMediaProgress'] ?? json['mediaProgress'];
    return AbsBook(
      id: '${json['id'] ?? ''}',
      title: '${metadata['title'] ?? json['title'] ?? '未命名有声书'}',
      author: '${metadata['authorName'] ?? ''}',
      narrator: metadata['narratorName'] is String ? '${metadata['narratorName']}' : ((metadata['narrators'] as List?)?.join('、') ?? ''),
      duration: (media['duration'] as num?)?.toDouble() ?? 0,
      progress: AbsProgress.fromJson(rawProgress is Map ? rawProgress.cast<String, dynamic>() : null),
    );
  }
}

class AbsChapter {
  const AbsChapter({required this.id, required this.title, required this.start, required this.end});
  final int id;
  final String title;
  final double start;
  final double end;
  factory AbsChapter.fromJson(Map<String, dynamic> json, int index) => AbsChapter(
    id: (json['id'] as num?)?.toInt() ?? index,
    title: '${json['title'] ?? '第 ${index + 1} 章'}',
    start: (json['start'] as num?)?.toDouble() ?? 0,
    end: (json['end'] as num?)?.toDouble() ?? 0,
  );
}

class AbsTrack {
  const AbsTrack({required this.startOffset, required this.duration, required this.contentUrl});
  final double startOffset;
  final double duration;
  final String contentUrl;
  factory AbsTrack.fromJson(Map<String, dynamic> json) => AbsTrack(
    startOffset: (json['startOffset'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    contentUrl: '${json['contentUrl'] ?? json['content_url'] ?? ''}',
  );
}

class AbsBookDetail {
  const AbsBookDetail({required this.book, required this.chapters, required this.tracks});
  final AbsBook book;
  final List<AbsChapter> chapters;
  final List<AbsTrack> tracks;
}

class AbsPlayback {
  const AbsPlayback({
    required this.url,
    required this.headers,
    required this.bookPosition,
    required this.requestedPosition,
    required this.trackPosition,
    required this.trackStarts,
    required this.duration,
    required this.exactTrack,
  });
  final String url;
  final Map<String, String> headers;
  /// Position represented by the beginning of the selected audio track.
  final double bookPosition;
  /// Absolute book position requested by the user, used for deterministic
  /// chapter navigation when a remote speaker cannot report direct-URL progress.
  final double requestedPosition;
  /// Offset inside the selected track at which playback should start.
  final double trackPosition;
  final List<double> trackStarts;
  final double duration;
  final bool exactTrack;
}

class AudiobookshelfException implements Exception {
  const AudiobookshelfException(this.message);
  final String message;
  @override String toString() => message;
}

class AudiobookshelfApi {
  AudiobookshelfApi(this.config, {http.Client? client}) : _client = client ?? http.Client();
  final AudiobookshelfConfig config;
  final http.Client _client;
  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('${config.normalizedBaseUrl}$path').replace(queryParameters: query);
  Map<String, String> get _headers => {'Authorization': 'Bearer ${config.apiKey.trim()}', 'Content-Type': 'application/json'};

  Future<List<AbsLibrary>> getLibraries() async {
    final body = await _get('/api/libraries');
    final raw = body is List ? body : (body['libraries'] as List? ?? const []);
    return [for (final item in raw) if (item is Map) AbsLibrary.fromJson(item.cast<String, dynamic>())];
  }

  Future<List<AbsBook>> getBooks(String libraryId, {String query = ''}) async {
    final dynamic body;
    if (query.trim().isNotEmpty) {
      body = await _get('/api/libraries/$libraryId/search', {'q': query.trim(), 'limit': '100'});
      final raw = body['book'] as List? ?? body['books'] as List? ?? body['libraryItems'] as List? ?? const [];
      return _parseBooks(raw);
    }
    body = await _get('/api/libraries/$libraryId/items', {'limit': '100', 'page': '0', 'sort': 'media.metadata.title', 'desc': '0', 'include': 'progress', 'expanded': '1'});
    return _parseBooks(body['results'] as List? ?? const []);
  }

  Future<List<AbsBook>> getContinueListening(String libraryId) async {
    final books = await getBooks(libraryId);
    final active = books.where((book) => book.progress.currentTime > 0 && !book.progress.isFinished).toList()
      ..sort((a, b) => b.progress.lastUpdate.compareTo(a.progress.lastUpdate));
    return active;
  }

  Future<AbsBookDetail> getBook(String itemId) async {
    final raw = await _get('/api/items/$itemId', {'expanded': '1', 'include': 'progress'});
    final item = (raw as Map).cast<String, dynamic>();
    final media = (item['media'] as Map?)?.cast<String, dynamic>() ?? const {};
    final chapters = media['chapters'] as List? ?? const [];
    final tracks = media['audioTracks'] as List? ?? const [];
    return AbsBookDetail(
      book: AbsBook.fromJson(item),
      chapters: [for (var i = 0; i < chapters.length; i++) if (chapters[i] is Map) AbsChapter.fromJson((chapters[i] as Map).cast<String, dynamic>(), i)],
      tracks: [for (final track in tracks) if (track is Map) AbsTrack.fromJson(track.cast<String, dynamic>())],
    );
  }

  Future<AbsPlayback> createPlayback(AbsBookDetail detail, {double? position}) async {
    final body = await _post('/api/items/${detail.book.id}/play', {
      'deviceInfo': {'deviceId': 'sonichub', 'deviceName': '音枢 SonicHub', 'clientName': 'SonicHub', 'clientVersion': '0.3.0'},
      'supportedMimeTypes': ['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/flac'],
      'forceDirectPlay': true,
      'mediaPlayer': 'sonichub-miot',
    });
    final rawTracks = body['audioTracks'] as List? ?? const [];
    final tracks = [for (final track in rawTracks) if (track is Map) AbsTrack.fromJson(track.cast<String, dynamic>())];
    final available = tracks.isNotEmpty ? tracks : detail.tracks;
    if (available.isEmpty) throw const AudiobookshelfException('Audiobookshelf 没有返回可播放音轨');
    final target = position ?? detail.book.progress.currentTime;
    var selected = available.first;
    for (final track in available) {
      final end = track.startOffset + track.duration;
      if (target >= track.startOffset && (track.duration <= 0 || target < end)) { selected = track; break; }
    }
    final uri = config.resolveContentUrl(selected.contentUrl);
    final url = uri.replace(queryParameters: {...uri.queryParameters, 'token': config.apiKey.trim()}).toString();
    final withinTrack = (target - selected.startOffset).clamp(0, selected.duration).toDouble();
    return AbsPlayback(
      url: url,
      headers: config.audioHeaders,
      bookPosition: selected.startOffset,
      requestedPosition: target,
      trackPosition: withinTrack,
      trackStarts: [
        for (final track in available) track.startOffset,
      ]..sort(),
      duration: detail.book.duration,
      // A remote speaker receives a direct URL and cannot seek inside it.
      exactTrack: withinTrack < 0.5,
    );
  }

  Future<void> updateProgress(String itemId, {required double currentTime, required double duration, bool isFinished = false}) => _patch('/api/me/progress/$itemId', {
    'currentTime': currentTime,
    'duration': duration,
    'progress': duration <= 0 ? 0 : (currentTime / duration).clamp(0, 1),
    'isFinished': isFinished,
  });

  List<AbsBook> _parseBooks(List raw) => [for (final item in raw) if (item is Map) AbsBook.fromJson(item.cast<String, dynamic>())];
  Future<dynamic> _get(String path, [Map<String, String>? query]) async => _decode(await _client.get(_uri(path, query), headers: _headers).timeout(const Duration(seconds: 15)));
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async => (_decode(await _client.post(_uri(path), headers: _headers, body: jsonEncode(data)).timeout(const Duration(seconds: 20))) as Map).cast<String, dynamic>();
  Future<void> _patch(String path, Map<String, dynamic> data) async { _decode(await _client.patch(_uri(path), headers: _headers, body: jsonEncode(data)).timeout(const Duration(seconds: 15))); }
  dynamic _decode(http.Response response) {
    dynamic body;
    try { body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body); } catch (_) { throw AudiobookshelfException('Audiobookshelf 返回了无法解析的数据（HTTP ${response.statusCode}）'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['message'] ?? body['error'] ?? '请求失败' : '请求失败';
      throw AudiobookshelfException('Audiobookshelf：$message（HTTP ${response.statusCode}）');
    }
    return body;
  }
}
