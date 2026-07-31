import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'local_audio_player.dart';
import 'models.dart';
import 'playback_context.dart';
import 'songloft_api.dart';

enum PlaybackPhase {
  idle,
  loading,
  buffering,
  playing,
  paused,
  completed,
  error,
}

class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.canToggle,
    required this.canStop,
    required this.canPrevious,
    required this.canNext,
    required this.canSeek,
  });

  final bool canToggle;
  final bool canStop;
  final bool canPrevious;
  final bool canNext;
  final bool canSeek;

  static const none = PlaybackCapabilities(
    canToggle: false,
    canStop: false,
    canPrevious: false,
    canNext: false,
    canSeek: false,
  );
}

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required SongloftApi api,
    LocalAudioPlayer? localPlayer,
    PlaybackContextStore? contextStore,
  })  : _api = api,
        localPlayer = localPlayer ?? LocalAudioPlayer(),
        _contextStore = contextStore ?? PlaybackContextStore();

  final SongloftApi _api;
  final PlaybackContextStore _contextStore;
  final LocalAudioPlayer localPlayer;

  SpeakerDevice? selectedDevice;
  DeviceStatus? status;
  PlaybackContext? context;
  String? diagnostic;
  String? operationMessage;
  bool busy = false;
  PlaybackPhase phase = PlaybackPhase.idle;

  List<MediaItem> _localQueue = const [];
  int _localIndex = -1;
  Timer? _statusTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  bool get isLocal => selectedDevice?.isLocal == true;

  PlaybackCapabilities get capabilities {
    final device = selectedDevice;
    if (device == null) return PlaybackCapabilities.none;
    if (context?.isAudiobook == true) {
      return PlaybackCapabilities(
        canToggle: true,
        canStop: true,
        canPrevious: context?.onPrevious != null,
        canNext: context?.onNext != null,
        canSeek: isLocal && context?.onSeek != null,
      );
    }
    if (isLocal) {
      return PlaybackCapabilities(
        canToggle: true,
        canStop: true,
        canPrevious: _localQueue.isNotEmpty && _localIndex > 0,
        canNext:
            _localQueue.isNotEmpty && _localIndex < _localQueue.length - 1,
        canSeek: status?.duration != null && status!.duration > 0,
      );
    }
    return const PlaybackCapabilities(
      canToggle: true,
      canStop: true,
      canPrevious: true,
      canNext: true,
      canSeek: false,
    );
  }

  Future<void> initialize() async {
    context = await _contextStore.load();
    _positionSubscription =
        localPlayer.positionStream.listen((_) => _updateLocalStatus());
    _durationSubscription =
        localPlayer.durationStream.listen((_) => _updateLocalStatus());
    _playerStateSubscription =
        localPlayer.playerStateStream.listen(_handlePlayerState);
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!busy && selectedDevice != null) {
        unawaited(refreshStatus(silent: true));
      }
    });
    notifyListeners();
  }

  void _handlePlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.loading) {
      phase = PlaybackPhase.loading;
    } else if (state.processingState == ProcessingState.buffering) {
      phase = PlaybackPhase.buffering;
    } else if (state.processingState == ProcessingState.completed) {
      phase = PlaybackPhase.completed;
    } else if (state.playing) {
      phase = PlaybackPhase.playing;
    } else if (state.processingState == ProcessingState.ready) {
      phase = PlaybackPhase.paused;
    } else {
      phase = PlaybackPhase.idle;
    }
    _updateLocalStatus();
  }

  Future<void> selectDevice(SpeakerDevice? device) async {
    selectedDevice = device;
    status = null;
    operationMessage = '已切换到 ${device?.name ?? '未选择设备'}';
    notifyListeners();
    await refreshStatus();
  }

  Future<void> refreshStatus({bool silent = false}) async {
    final device = selectedDevice;
    if (device == null) return;
    if (device.isLocal) {
      _updateLocalStatus();
      return;
    }
    if (!silent) {
      busy = true;
      diagnostic = null;
      notifyListeners();
    }
    try {
      final nextStatus = await _api.getStatus(device);
      status = nextStatus;
      if (nextStatus.currentSong != null &&
          (context == null || context!.source == PlaybackSource.songloft)) {
        context = PlaybackContext.songloft(nextStatus.currentSong!);
      }
    } catch (error) {
      diagnostic = error.toString();
      phase = PlaybackPhase.error;
    } finally {
      if (!silent) busy = false;
      notifyListeners();
    }
  }

  void _updateLocalStatus() {
    if (!isLocal) return;
    status = DeviceStatus(
      state: localPlayer.isPlaying ? 'playing' : 'paused',
      volume: null,
      position: localPlayer.position,
      duration: localPlayer.duration,
      currentIndex: _localIndex,
      playlistId: 0,
      playlistName: '本机播放',
      currentSong: null,
    );
    notifyListeners();
  }

  Future<void> playLocal(
    MediaItem song, {
    required String url,
    Map<String, String> headers = const {},
    List<MediaItem> queue = const [],
    int index = -1,
  }) async {
    if (url.trim().isEmpty) {
      diagnostic = '这首歌曲没有可用的播放地址';
      phase = PlaybackPhase.error;
      notifyListeners();
      return;
    }
    await _run(() async {
      phase = PlaybackPhase.loading;
      await localPlayer.playUrl(url, headers: headers);
      await _contextStore.clear();
      _localQueue = queue.isEmpty ? [song] : List<MediaItem>.of(queue);
      _localIndex = queue.isEmpty ? 0 : index;
      context = PlaybackContext.local(
        title: song.title,
        subtitle: song.subtitle,
        coverUrl: song.coverUrl,
        mediaId: '${song.id}',
        duration: song.duration,
      );
      operationMessage = '正在本机播放';
      _updateLocalStatus();
    });
  }

  Future<void> playLocalUrl(
    String url, {
    double initialPosition = 0,
    Map<String, String> headers = const {},
  }) async {
    await _run(() async {
      phase = PlaybackPhase.loading;
      await localPlayer.playUrl(
        url.trim(),
        headers: headers,
        initialPosition: initialPosition,
      );
      await _contextStore.clear();
      final uri = Uri.parse(url);
      _localQueue = const [];
      _localIndex = -1;
      context = PlaybackContext.local(
        title: uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
            ? '音频直链'
            : Uri.decodeComponent(uri.pathSegments.last),
        subtitle: uri.host,
        mediaId: url,
      );
      operationMessage = '正在本机播放';
      _updateLocalStatus();
    });
  }

  Future<void> toggle() async {
    if (isLocal) {
      if (localPlayer.isPlaying) {
        await localPlayer.pause();
      } else {
        unawaited(localPlayer.resume());
      }
      _updateLocalStatus();
      return;
    }
    await _control(_api.togglePlayback);
  }

  Future<void> stop() async {
    if (isLocal) {
      await localPlayer.stop();
      phase = PlaybackPhase.idle;
      operationMessage = '本机播放已停止';
      _updateLocalStatus();
      return;
    }
    await _control(_api.stop);
  }

  Future<void> previous({
    required String Function(MediaItem item) resolveUrl,
    required Map<String, String> Function(String url) headersFor,
  }) async {
    final contextual = context?.onPrevious;
    if (context?.isAudiobook == true && contextual != null) {
      await _runContextAction(contextual);
      return;
    }
    if (isLocal) {
      if (_localQueue.isEmpty || _localIndex <= 0) {
        operationMessage = '已经是本机播放队列第一首';
        notifyListeners();
        return;
      }
      final nextIndex = _localIndex - 1;
      final item = _localQueue[nextIndex];
      final url = resolveUrl(item);
      await playLocal(
        item,
        url: url,
        headers: headersFor(url),
        queue: _localQueue,
        index: nextIndex,
      );
      return;
    }
    if (contextual != null) {
      await _runContextAction(contextual);
    } else {
      await _control(_api.previous);
    }
  }

  Future<void> next({
    required String Function(MediaItem item) resolveUrl,
    required Map<String, String> Function(String url) headersFor,
  }) async {
    final contextual = context?.onNext;
    if (context?.isAudiobook == true && contextual != null) {
      await _runContextAction(contextual);
      return;
    }
    if (isLocal) {
      if (_localQueue.isEmpty ||
          _localIndex < 0 ||
          _localIndex >= _localQueue.length - 1) {
        operationMessage = '已经是本机播放队列最后一首';
        notifyListeners();
        return;
      }
      final nextIndex = _localIndex + 1;
      final item = _localQueue[nextIndex];
      final url = resolveUrl(item);
      await playLocal(
        item,
        url: url,
        headers: headersFor(url),
        queue: _localQueue,
        index: nextIndex,
      );
      return;
    }
    if (contextual != null) {
      await _runContextAction(contextual);
    } else {
      await _control(_api.next);
    }
  }

  Future<void> seek(double position) async {
    if (isLocal) {
      await localPlayer.seek(position);
      _updateLocalStatus();
      return;
    }
    final contextual = context?.onSeek;
    if (contextual != null) {
      await _runContextAction(() => contextual(position));
    }
  }

  Future<void> setVolume(double value) =>
      _control((device) => _api.setVolume(device, value.round()));

  Future<void> diagnose() async {
    await _run(() async {
      await _api.testConnection();
      final devices = await _api.getDevices();
      diagnostic = devices.isEmpty
          ? 'Songloft 已连接，但 MIoT 插件没有返回音箱。'
          : '连接正常，MIoT 插件返回 ${devices.length} 台音箱。';
    });
  }

  void setAudiobookContext(PlaybackContext nextContext) {
    context = nextContext;
    operationMessage = '已投送到 ${selectedDevice?.name ?? '当前音箱'}';
    unawaited(_contextStore.save(nextContext));
    notifyListeners();
    unawaited(refreshStatus());
  }

  void clearExternalContext() {
    unawaited(_contextStore.clear());
    context = null;
    operationMessage = '正在读取 Songloft 播放状态';
    notifyListeners();
    unawaited(refreshStatus());
  }

  void setDirectUrlContext(String url) {
    final uri = Uri.parse(url);
    final nextContext = PlaybackContext(
      source: PlaybackSource.directUrl,
      title: uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
          ? '音频直链'
          : Uri.decodeComponent(uri.pathSegments.last),
      subtitle: uri.host,
      mediaId: url,
    );
    context = nextContext;
    operationMessage = '直链已投送到 ${selectedDevice?.name ?? '当前音箱'}';
    unawaited(_contextStore.save(nextContext));
    notifyListeners();
  }

  Future<void> _control(
    Future<void> Function(SpeakerDevice device) action,
  ) async {
    final device = selectedDevice;
    if (device == null || busy) return;
    await _run(() async {
      await action(device);
      operationMessage = '操作已发送到 ${device.name}';
      await refreshStatus(silent: true);
    });
  }

  Future<void> _runContextAction(Future<void> Function() action) =>
      _run(() async {
        await action();
        await refreshStatus(silent: true);
      });

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    diagnostic = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      diagnostic = error.toString();
      phase = PlaybackPhase.error;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    unawaited(localPlayer.dispose());
    super.dispose();
  }
}
