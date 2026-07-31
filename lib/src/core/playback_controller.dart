import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'local_audio_player.dart';
import 'models.dart';
import 'playback_context.dart';
import 'playback_engine.dart';
import 'songloft_api.dart';

enum PlaybackPhase { idle, loading, buffering, playing, paused, completed, error }

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
        _contextStore = contextStore ?? PlaybackContextStore(),
        _localEngine = LocalPlaybackEngine(api: api, player: localPlayer),
        _remoteEngine = SongloftPlaybackEngine(api);

  final SongloftApi _api;
  final PlaybackContextStore _contextStore;
  final LocalPlaybackEngine _localEngine;
  final SongloftPlaybackEngine _remoteEngine;

  SpeakerDevice? selectedDevice;
  DeviceStatus? status;
  PlaybackContext? context;
  String? diagnostic;
  String? operationMessage;
  bool busy = false;
  PlaybackPhase phase = PlaybackPhase.idle;

  Timer? _statusTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  final RequestGeneration _generation = RequestGeneration();
  bool _disposed = false;

  bool get isLocal => selectedDevice?.isLocal == true;
  LocalAudioPlayer get localPlayer => _localEngine.player;
  PlaybackEngine get _engine => isLocal ? _localEngine : _remoteEngine;

  PlaybackCapabilities get capabilities {
    if (selectedDevice == null) return PlaybackCapabilities.none;
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
        canPrevious: _localEngine.canPrevious,
        canNext: _localEngine.canNext,
        canSeek: (status?.duration ?? 0) > 0,
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
    _positionSubscription = localPlayer.positionStream.listen((_) => _syncLocal());
    _durationSubscription = localPlayer.durationStream.listen((_) => _syncLocal());
    _playerStateSubscription = localPlayer.playerStateStream.listen(_handlePlayerState);
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!busy && selectedDevice != null) unawaited(refreshStatus(silent: true));
    });
    _notify();
  }

  void _handlePlayerState(PlayerState value) {
    phase = switch (value.processingState) {
      ProcessingState.loading => PlaybackPhase.loading,
      ProcessingState.buffering => PlaybackPhase.buffering,
      ProcessingState.completed => PlaybackPhase.completed,
      ProcessingState.ready => value.playing ? PlaybackPhase.playing : PlaybackPhase.paused,
      _ => PlaybackPhase.idle,
    };
    _syncLocal();
  }

  Future<void> selectDevice(SpeakerDevice? device) async {
    _generation.advance();
    selectedDevice = device;
    status = null;
    operationMessage = '已切换到 ${device?.name ?? '未选择设备'}';
    _notify();
    await refreshStatus();
  }

  Future<void> refreshStatus({bool silent = false}) async {
    final device = selectedDevice;
    if (device == null) return;
    final generation = _generation.current;
    if (!silent) {
      busy = true;
      diagnostic = null;
      _notify();
    }
    try {
      final nextStatus = await _engine.refresh(device);
      if (!_isCurrent(generation, device)) return;
      status = nextStatus;
      if (nextStatus?.currentSong != null &&
          (context == null || context!.source == PlaybackSource.songloft)) {
        context = PlaybackContext.songloft(nextStatus!.currentSong!);
      }
    } catch (error) {
      if (_isCurrent(generation, device)) {
        diagnostic = error.toString();
        phase = PlaybackPhase.error;
      }
    } finally {
      if (!silent && _isCurrent(generation, device)) busy = false;
      _notify();
    }
  }

  bool _isCurrent(int generation, SpeakerDevice device) =>
      !_disposed &&
      _generation.isCurrent(generation) &&
      selectedDevice?.id == device.id &&
      selectedDevice?.accountId == device.accountId;

  void _syncLocal() {
    if (!isLocal || _disposed) return;
    status = _localEngine.status;
    _notify();
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
      _notify();
      return;
    }
    await _run(() async {
      phase = PlaybackPhase.loading;
      await _localEngine.playMedia(song, url: url, headers: headers, queue: queue, index: index);
      await _contextStore.clear();
      context = PlaybackContext.local(
        title: song.title,
        subtitle: song.subtitle,
        coverUrl: song.coverUrl,
        mediaId: '${song.id}',
        duration: song.duration,
      );
      operationMessage = '正在本机播放';
      _syncLocal();
    });
  }

  Future<void> playLocalUrl(
    String url, {
    double initialPosition = 0,
    Map<String, String> headers = const {},
  }) => _run(() async {
        phase = PlaybackPhase.loading;
        await _localEngine.playUrl(url.trim(), initialPosition: initialPosition, headers: headers);
        await _contextStore.clear();
        final uri = Uri.parse(url);
        context = PlaybackContext.local(
          title: uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
              ? '音频直链'
              : Uri.decodeComponent(uri.pathSegments.last),
          subtitle: uri.host,
          mediaId: url,
        );
        operationMessage = '正在本机播放';
        _syncLocal();
      });

  Future<void> toggle() => _control((engine, device) => engine.toggle(device));

  Future<void> stop() => _control((engine, device) async {
        await engine.stop(device);
        if (engine.isLocal) phase = PlaybackPhase.idle;
      });

  Future<void> previous() async {
    final contextual = context?.onPrevious;
    if (context?.isAudiobook == true && contextual != null) {
      await _runContextAction(contextual);
    } else if (isLocal && !_localEngine.canPrevious) {
      operationMessage = '已经是本机播放队列第一首';
      _notify();
    } else if (contextual != null) {
      await _runContextAction(contextual);
    } else {
      await _control((engine, device) => engine.previous(device));
    }
  }

  Future<void> next() async {
    final contextual = context?.onNext;
    if (context?.isAudiobook == true && contextual != null) {
      await _runContextAction(contextual);
    } else if (isLocal && !_localEngine.canNext) {
      operationMessage = '已经是本机播放队列最后一首';
      _notify();
    } else if (contextual != null) {
      await _runContextAction(contextual);
    } else {
      await _control((engine, device) => engine.next(device));
    }
  }

  Future<void> seek(double position) {
    final contextual = context?.onSeek;
    if (contextual != null) return _runContextAction(() => contextual(position));
    return _control((engine, device) => engine.seek(device, position));
  }

  Future<void> setVolume(double value) =>
      _control((engine, device) => engine.setVolume(device, value));

  Future<void> diagnose() => _run(() async {
        await _api.testConnection();
        final devices = await _api.getDevices();
        diagnostic = devices.isEmpty
            ? 'Songloft 已连接，但 MIoT 插件没有返回音箱。'
            : '连接正常，MIoT 插件返回 ${devices.length} 台音箱。';
      });

  void setAudiobookContext(PlaybackContext value) {
    context = value;
    operationMessage = '已投送到 ${selectedDevice?.name ?? '当前音箱'}';
    unawaited(_contextStore.save(value));
    _notify();
    unawaited(refreshStatus());
  }

  void clearExternalContext() {
    unawaited(_contextStore.clear());
    context = null;
    operationMessage = '正在读取 Songloft 播放状态';
    _notify();
    unawaited(refreshStatus());
  }

  void setDirectUrlContext(String url) {
    final uri = Uri.parse(url);
    final value = PlaybackContext(
      source: PlaybackSource.directUrl,
      title: uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
          ? '音频直链'
          : Uri.decodeComponent(uri.pathSegments.last),
      subtitle: uri.host,
      mediaId: url,
    );
    context = value;
    operationMessage = '直链已投送到 ${selectedDevice?.name ?? '当前音箱'}';
    unawaited(_contextStore.save(value));
    _notify();
  }

  Future<void> _control(
    Future<void> Function(PlaybackEngine engine, SpeakerDevice device) action,
  ) async {
    final device = selectedDevice;
    if (device == null) return;
    await _run(() async {
      await action(_engine, device);
      if (_engine.isLocal) _syncLocalMediaContext();
      operationMessage = '操作已发送到 ${device.name}';
      await refreshStatus(silent: true);
    });
  }

  void _syncLocalMediaContext() {
    final item = _localEngine.currentItem;
    if (item == null || context?.isAudiobook == true) return;
    context = PlaybackContext.local(
      title: item.title,
      subtitle: item.subtitle,
      coverUrl: item.coverUrl,
      mediaId: '${item.id}',
      duration: item.duration,
    );
  }

  Future<void> _runContextAction(Future<void> Function() action) async {
    try {
      // Audiobook callbacks re-enter this controller through playLocalUrl.
      // Do not hold the outer busy lock or the actual chapter play is dropped.
      await action();
      await refreshStatus(silent: true);
    } catch (error) {
      diagnostic = error.toString();
      phase = PlaybackPhase.error;
      _notify();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    final generation = _generation.current;
    busy = true;
    diagnostic = null;
    _notify();
    try {
      await action();
    } catch (error) {
      if (_generation.isCurrent(generation)) {
        diagnostic = error.toString();
        phase = PlaybackPhase.error;
      }
    } finally {
      if (_generation.isCurrent(generation)) busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation.advance();
    _statusTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    unawaited(_localEngine.dispose());
    super.dispose();
  }
}
