import 'models.dart';

enum PlaybackSource { songloft, audiobookshelf, directUrl }

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
      };

  factory PlaybackContext.songloft(MediaItem song) => PlaybackContext(
        source: PlaybackSource.songloft,
        title: song.title,
        subtitle: song.subtitle,
        coverUrl: song.coverUrl,
        mediaId: '${song.id}',
        duration: song.duration,
      );
}
