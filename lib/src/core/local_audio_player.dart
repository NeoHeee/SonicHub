import 'package:just_audio/just_audio.dart';

class LocalAudioPlayer {
  LocalAudioPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> playUrl(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final value = url.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty || uri == null || !uri.isAbsolute) {
      throw const FormatException('没有可播放的音频地址');
    }
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          uri,
          headers: headers.isEmpty ? null : headers,
        ),
      );
      await _player.play();
    } on PlayerException catch (error) {
      final detail = error.message.trim();
      throw FormatException(
        detail.isEmpty
            ? '音频源无法访问（${error.code}）'
            : '音频源无法访问：$detail',
      );
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> stop() => _player.stop();
  Future<void> seek(double seconds) =>
      _player.seek(Duration(milliseconds: (seconds * 1000).round()));

  double get position => _player.position.inMilliseconds / 1000;
  double get duration => (_player.duration?.inMilliseconds ?? 0) / 1000;
  bool get isPlaying => _player.playing;

  Future<void> dispose() => _player.dispose();
}
