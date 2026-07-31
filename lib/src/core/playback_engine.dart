import 'dart:async';

import 'local_audio_player.dart';
import 'models.dart';
import 'songloft_api.dart';

class RequestGeneration {
  int _value = 0;

  int get current => _value;
  int advance() => ++_value;
  bool isCurrent(int value) => value == _value;
}

abstract class PlaybackEngine {
  bool get isLocal;
  DeviceStatus? get status;

  Future<DeviceStatus?> refresh(SpeakerDevice device);
  Future<void> toggle(SpeakerDevice device);
  Future<void> stop(SpeakerDevice device);
  Future<void> previous(SpeakerDevice device);
  Future<void> next(SpeakerDevice device);
  Future<void> seek(SpeakerDevice device, double position);
  Future<void> setVolume(SpeakerDevice device, double value);
}

class LocalPlaybackEngine implements PlaybackEngine {
  LocalPlaybackEngine({
    required SongloftApi api,
    LocalAudioPlayer? player,
  })  : _api = api,
        player = player ?? LocalAudioPlayer();

  final SongloftApi _api;
  final LocalAudioPlayer player;
  List<MediaItem> _queue = const [];
  int _index = -1;

  List<MediaItem> get queue => List.unmodifiable(_queue);
  int get index => _index;
  MediaItem? get currentItem =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  bool get canPrevious => _queue.isNotEmpty && _index > 0;
  bool get canNext => _queue.isNotEmpty && _index < _queue.length - 1;

  @override
  bool get isLocal => true;

  @override
  DeviceStatus get status => DeviceStatus(
        state: player.isPlaying ? 'playing' : 'paused',
        volume: null,
        position: player.position,
        duration: player.duration,
        currentIndex: _index,
        playlistId: 0,
        playlistName: '本机播放',
        currentSong: null,
      );

  Future<void> playMedia(
    MediaItem item, {
    required String url,
    Map<String, String> headers = const {},
    List<MediaItem> queue = const [],
    int index = -1,
  }) async {
    await player.playUrl(url, headers: headers);
    _queue = queue.isEmpty ? [item] : List<MediaItem>.of(queue);
    _index = queue.isEmpty ? 0 : index;
  }

  Future<void> playUrl(
    String url, {
    double initialPosition = 0,
    Map<String, String> headers = const {},
  }) async {
    await player.playUrl(
      url,
      headers: headers,
      initialPosition: initialPosition,
    );
    _queue = const [];
    _index = -1;
  }

  @override
  Future<DeviceStatus> refresh(SpeakerDevice device) async => status;

  @override
  Future<void> toggle(SpeakerDevice device) async {
    if (player.isPlaying) {
      await player.pause();
    } else {
      unawaited(player.resume());
    }
  }

  @override
  Future<void> stop(SpeakerDevice device) => player.stop();

  @override
  Future<void> previous(SpeakerDevice device) => _playQueueIndex(_index - 1);

  @override
  Future<void> next(SpeakerDevice device) => _playQueueIndex(_index + 1);

  Future<void> _playQueueIndex(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= _queue.length) return;
    final item = _queue[nextIndex];
    final url = _api.resolveAudioUrl(item.playUrl);
    await player.playUrl(url, headers: _api.audioHeadersFor(url));
    _index = nextIndex;
  }

  @override
  Future<void> seek(SpeakerDevice device, double position) =>
      player.seek(position);

  @override
  Future<void> setVolume(SpeakerDevice device, double value) async {}

  Future<void> dispose() => player.dispose();
}

class SongloftPlaybackEngine implements PlaybackEngine {
  SongloftPlaybackEngine(this._api);

  final SongloftApi _api;
  DeviceStatus? _status;

  @override
  bool get isLocal => false;

  @override
  DeviceStatus? get status => _status;

  @override
  Future<DeviceStatus> refresh(SpeakerDevice device) async {
    final value = await _api.getStatus(device);
    _status = value;
    return value;
  }

  @override
  Future<void> toggle(SpeakerDevice device) => _api.togglePlayback(device);

  @override
  Future<void> stop(SpeakerDevice device) => _api.stop(device);

  @override
  Future<void> previous(SpeakerDevice device) => _api.previous(device);

  @override
  Future<void> next(SpeakerDevice device) => _api.next(device);

  @override
  Future<void> seek(SpeakerDevice device, double position) async {}

  @override
  Future<void> setVolume(SpeakerDevice device, double value) =>
      _api.setVolume(device, value.round());
}
