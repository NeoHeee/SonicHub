import 'package:just_audio/just_audio.dart';

class LocalAudioPlayer {
  LocalAudioPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> playUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) throw const FormatException('没有可播放的音频地址');
    await _player.setUrl(value);
    await _player.play();
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
