import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

enum PlaybackSource { songloft, audiobookshelf, directUrl, local }

class PlaybackContext {
  const PlaybackContext({
    required this.source,
    required this.title,
    this.subtitle = '',
    this.coverUrl,
    this.mediaId,
    this.position = 0,
    this.duration = 0,
    this.syncMessage,
    this.onPrevious,
    this.onNext,
    this.onSeek,
  });

  final PlaybackSource source;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? mediaId;
  final double position;
  final double duration;
  final String? syncMessage;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;
  final Future<void> Function(double position)? onSeek;

  bool get isAudiobook => source == PlaybackSource.audiobookshelf;
  String get sourceLabel => switch (source) {
        PlaybackSource.songloft => 'Songloft',
        PlaybackSource.audiobookshelf => 'Audiobookshelf',
        PlaybackSource.directUrl => '音频直链',
        PlaybackSource.local => '本机播放',
      };

  factory PlaybackContext.songloft(MediaItem song) => PlaybackContext(
        source: PlaybackSource.songloft,
        title: song.title,
        subtitle: song.subtitle,
        coverUrl: song.coverUrl,
        mediaId: '${song.id}',
      duration: song.duration,
      );

  factory PlaybackContext.local({
    required String title,
    String subtitle = '',
    String? coverUrl,
    String? mediaId,
    double duration = 0,
  }) =>
      PlaybackContext(
        source: PlaybackSource.local,
        title: title,
        subtitle: subtitle,
        coverUrl: coverUrl,
        mediaId: mediaId,
        duration: duration,
      );
}

/// Persists only the descriptive part of the current playback context.
/// Callback functions are rebound when the source page is opened again.
class PlaybackContextStore {
  PlaybackContextStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'sonichub_last_playback_context';
  final FlutterSecureStorage _storage;

  Future<void> save(PlaybackContext context) async {
    if (context.source != PlaybackSource.audiobookshelf &&
        context.source != PlaybackSource.directUrl) {
      return;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'source': context.source.name,
        'title': context.title,
        'subtitle': context.subtitle,
        'coverUrl': context.coverUrl,
        'mediaId': context.mediaId,
        'position': context.position,
        'duration': context.duration,
        'syncMessage': context.syncMessage,
      }),
    );
  }

  Future<PlaybackContext?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final sourceName = '${json['source'] ?? ''}';
      final source = PlaybackSource.values.firstWhere(
        (item) => item.name == sourceName,
        orElse: () => PlaybackSource.directUrl,
      );
      if (source != PlaybackSource.audiobookshelf &&
          source != PlaybackSource.directUrl) {
        return null;
      }
      return PlaybackContext(
        source: source,
        title: '${json['title'] ?? ''}',
        subtitle: '${json['subtitle'] ?? ''}',
        coverUrl: json['coverUrl']?.toString(),
        mediaId: json['mediaId']?.toString(),
        position: (json['position'] as num?)?.toDouble() ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        syncMessage: json['syncMessage']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}
