import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audiobookshelf_api.dart';
import '../../core/config_store.dart';
import '../../core/models.dart';
import '../../core/playback_controller.dart';
import '../../core/playback_context.dart';
import '../audiobookshelf/audiobookshelf_page.dart';
import '../../core/server_config.dart';
import '../../core/songloft_api.dart';
import '../speakers/speakers_page.dart';
import '../url_player/url_player_sheet.dart';

class MainShell extends StatefulWidget {
  const MainShell({required this.api, required this.config, super.key});
  final SongloftApi api;
  final ServerConfig config;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late Future<List<SpeakerDevice>> _devices;
  late final PlaybackController _controller;
  final _configStore = ConfigStore();

  SpeakerDevice? get _selectedDevice => _controller.selectedDevice;
  DeviceStatus? get _status => _controller.status;
  String? get _diagnostic => _controller.diagnostic;
  bool get _busy => _controller.busy;
  PlaybackContext? get _playback => _controller.context;
  String? get _operationMessage => _controller.operationMessage;

  @override
  void initState() {
    super.initState();
    _controller = PlaybackController(api: widget.api)
      ..addListener(_onPlaybackChanged);
    _devices = _controller.initialize().then((_) => _loadDevices());
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onPlaybackChanged)
      ..dispose();
    super.dispose();
  }

  Future<List<SpeakerDevice>> _loadDevices() async {
    final devices = await widget.api.getDevices();
    final saved = await _configStore.loadSelectedDevice();
    if (devices.isNotEmpty && _controller.selectedDevice == null) {
      final selected = saved == null
          ? devices.first
          : devices.firstWhere(
              (item) =>
                  item.id == saved.deviceId &&
                  item.accountId == saved.accountId,
              orElse: () => devices.first,
            );
      await _controller.selectDevice(selected);
    }
    return devices;
  }

  Future<void> _refreshDevices() async {
    final future = _loadDevices();
    setState(() => _devices = future);
    try {
      final devices = await future;
      if (!mounted) return;
      final previous = _controller.selectedDevice;
      final next = previous?.isLocal == true
          ? SpeakerDevice.local
          : devices.isEmpty
              ? null
              : devices.firstWhere(
                  (item) =>
                      item.id == previous?.id &&
                      item.accountId == previous?.accountId,
                  orElse: () => devices.first,
                );
      await _controller.selectDevice(next);
    } catch (_) {}
  }

  Future<void> _selectDevice(SpeakerDevice? device) async {
    if (device != null && !device.isLocal) {
      await _configStore.saveSelectedDevice(device.accountId, device.id);
    }
    await _controller.selectDevice(device);
  }

  Future<void> _refreshStatus({bool silent = false}) =>
      _controller.refreshStatus(silent: silent);

  Future<void> _playLocal(
    MediaItem song, {
    List<MediaItem> queue = const [],
    int index = -1,
  }) async {
    if (song.playUrl.trim().isEmpty) {
      return;
    }
    final url = widget.api.resolveAudioUrl(song.playUrl);
    await _controller.playLocal(
      song,
      url: url,
      headers: widget.api.audioHeadersFor(url),
      queue: queue,
      index: index,
    );
  }

  Future<void> _playLocalUrl(
    String url, [
    double startPosition = 0,
    Map<String, String> headers = const {},
  ]) =>
      _controller.playLocalUrl(
        url,
        initialPosition: startPosition,
        headers: headers,
      );

  Future<void> _togglePlayback() => _controller.toggle();
  Future<void> _stopPlayback() => _controller.stop();
  Future<void> _setVolume(double value) => _controller.setVolume(value);

  void _showAudiobook(
    AbsBook book,
    String? chapterTitle,
    String? coverUrl,
    double bookPosition,
    Future<void> Function() onPrevious,
    Future<void> Function() onNext,
    Future<void> Function(double position) onSeek,
  ) {
    final local = _selectedDevice?.isLocal == true;
    final context = PlaybackContext(
        source: PlaybackSource.audiobookshelf,
        title: book.title,
        subtitle: [
          if (chapterTitle?.trim().isNotEmpty == true) chapterTitle!.trim(),
          if (book.subtitle.trim().isNotEmpty) book.subtitle.trim(),
        ].join(' · '),
        coverUrl: coverUrl,
        mediaId: book.id,
        position: bookPosition,
        duration: book.duration,
        syncMessage: local
            ? '本机播放 · 支持精确拖动'
            : '音箱直链播放 · 支持章节切换，不支持进度跳转',
        onPrevious: onPrevious,
        onNext: onNext,
        onSeek: local ? onSeek : null,
      );
    _controller.setAudiobookContext(context);
  }

  void _clearExternalPlayback() => _controller.clearExternalContext();

  void _showDirectUrl(String url) => _controller.setDirectUrlContext(url);

  Future<void> _previous() => _controller.previous(
        resolveUrl: widget.api.resolveAudioUrl,
        headersFor: widget.api.audioHeadersFor,
      );

  Future<void> _next() => _controller.next(
        resolveUrl: widget.api.resolveAudioUrl,
        headersFor: widget.api.audioHeadersFor,
      );

  Future<void> _seek(double position) => _controller.seek(position);

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更换账号或服务器？'),
        content: const Text('将返回连接页面，已保存的配置不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _diagnose() => _controller.diagnose();

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(
        selectedDevice: _selectedDevice,
        status: _status,
        capabilities: _controller.capabilities,
        busy: _busy,
        diagnostic: _diagnostic,
        onRefresh: _refreshStatus,
        onRefreshStatus: _refreshStatus,
        onPrevious: _previous,
        onToggle: _togglePlayback,
        onStop: _stopPlayback,
        onNext: _next,
        onVolumeChanged: _setVolume,
        onSeek: _seek,
        playback: _playback,
        operationMessage: _operationMessage,
        onOpenDevice: () => setState(() => _index = 3),
        onOpenSource: () => setState(() => _index = _playback?.isAudiobook == true ? 2 : 1),
        onPlayUrl: _selectedDevice == null
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => UrlPlayerSheet(
                    api: widget.api,
                    device: _selectedDevice!,
                    onPlayed: _showDirectUrl,
                    localPlayer:
                        _selectedDevice!.isLocal ? _controller.localPlayer : null,
                    onLocalPlayed: _playLocalUrl,
                  ),
                ).then((_) => _refreshStatus()),
      ),
      _LibraryPage(
        api: widget.api,
        device: _selectedDevice,
        onPlayed: _clearExternalPlayback,
        onPlayLocal: _playLocal,
        onOpenAudiobook: () => setState(() => _index = 2),
        onOpenDirectUrl: _selectedDevice == null
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => UrlPlayerSheet(
                    api: widget.api,
                    device: _selectedDevice!,
                    onPlayed: _showDirectUrl,
                    localPlayer:
                        _selectedDevice!.isLocal ? _controller.localPlayer : null,
                    onLocalPlayed: _playLocalUrl,
                  ),
                ).then((_) => _refreshStatus()),
      ),
      AudiobookshelfPage(
        songloftApi: widget.api,
        device: _selectedDevice,
        onPlayed: _showAudiobook,
        onLocalPlayed: _playLocalUrl,
        localPosition: () async => _controller.localPlayer.position,
      ),
      SpeakersPage(
        api: widget.api,
        devices: _devices,
        selectedDevice: _selectedDevice,
        onSelected: _selectDevice,
        onRefresh: _refreshDevices,
      ),
      _SettingsPage(
        config: widget.config,
        busy: _busy,
        diagnostic: _diagnostic,
        onDiagnose: _diagnose,
        onReconnect: _logout,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '播放',
          ),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: '音乐'),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: '有声书',
          ),
          NavigationDestination(
            icon: Icon(Icons.speaker_outlined),
            selectedIcon: Icon(Icons.speaker),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
      ),
    ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.selectedDevice,
    required this.status,
    required this.capabilities,
    required this.busy,
    required this.diagnostic,
    required this.onRefresh,
    required this.onRefreshStatus,
    required this.onPrevious,
    required this.onToggle,
    required this.onStop,
    required this.onNext,
    required this.onVolumeChanged,
    required this.onSeek,
    required this.playback,
    required this.operationMessage,
    required this.onOpenDevice,
    required this.onOpenSource,
    required this.onPlayUrl,
  });

  final SpeakerDevice? selectedDevice;
  final DeviceStatus? status;
  final PlaybackCapabilities capabilities;
  final bool busy;
  final String? diagnostic;
  final Future<void> Function() onRefresh;
  final VoidCallback onRefreshStatus;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final VoidCallback onNext;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSeek;
  final PlaybackContext? playback;
  final String? operationMessage;
  final VoidCallback onOpenDevice;
  final VoidCallback onOpenSource;
  final VoidCallback? onPlayUrl;

  String _formatTime(double seconds) {
    final value = seconds.round().clamp(0, 999999);
    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;
    final remaining = value % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}'
        : '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final song = status?.currentSong;
    final isAudiobook = playback?.isAudiobook == true;
    final title = playback?.title ?? song?.title ?? '暂无播放内容';
    final subtitle = playback?.subtitle.isNotEmpty == true
        ? playback!.subtitle
        :
        (song?.subtitle.isNotEmpty == true
            ? song!.subtitle
            : (status?.playlistName.isNotEmpty == true
                ? status!.playlistName
                : '从曲库或有声书中选择内容'));
    final coverUrl = playback?.coverUrl ?? song?.coverUrl;
    final statusDuration = status?.duration ?? 0;
    final statusPosition = status?.position ?? 0;
    final duration = isAudiobook && (playback?.duration ?? 0) > 0
        ? playback!.duration
        : statusDuration;
    final position = (isAudiobook
        ? ((playback?.position ?? 0) + statusPosition).clamp(0, duration)
        : statusPosition).toDouble();

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The page sits above the bottom navigation bar. Keep the artwork
          // responsive so the complete player remains visible on short phones.
          final compact = constraints.maxHeight < 780;
          final artworkSize = (constraints.maxHeight * 0.28)
              .clamp(compact ? 180.0 : 200.0, compact ? 205.0 : 225.0)
              .toDouble();
          final sectionGap = compact ? 8.0 : 10.0;

          return RefreshIndicator(
            onRefresh: onRefresh,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primaryContainer.withValues(alpha: 0.82),
                    scheme.surface,
                    scheme.surface,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, compact ? 0 : 4, 20, compact ? 6 : 10),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isAudiobook ? '正在收听' : '正在播放',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新播放状态',
                      onPressed: selectedDevice == null || busy ? null : onRefreshStatus,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: '当前设备',
                      onPressed: onOpenDevice,
                      icon: const Icon(Icons.speaker_outlined),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 4 : 8),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: artworkSize),
                    child: SizedBox(
                      height: artworkSize,
                      child: AspectRatio(
                        aspectRatio: isAudiobook ? 0.78 : 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 24,
                                  offset: Offset(0, 12),
                                  color: Color(0x33000000),
                                ),
                              ],
                            ),
                            child: coverUrl?.trim().isNotEmpty == true
                                ? Image.network(
                                    coverUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _ArtworkFallback(isAudiobook: isAudiobook),
                                  )
                                : _ArtworkFallback(isAudiobook: isAudiobook),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: sectionGap),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Chip(
                    avatar: Icon(
                      isAudiobook ? Icons.auto_stories : Icons.library_music,
                      size: 18,
                    ),
                    label: Text('${playback?.sourceLabel ?? 'Songloft'} · ${isAudiobook ? '有声书' : '音乐'}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(height: compact ? 4 : 8),
                _SeekSlider(
                  position: position,
                  duration: duration,
                  enabled: selectedDevice?.isLocal == true &&
                      !busy &&
                      duration > 0 &&
                      capabilities.canSeek,
                  onSeek: onSeek,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(position)),
                    Text(_formatTime(duration)),
                  ],
                ),
                if (isAudiobook) ...[
                  const SizedBox(height: 4),
                  Text(
                    playback?.syncMessage ?? '章节播放 · 进度自动回传',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                SizedBox(height: compact ? 4 : 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: isAudiobook ? '上一章' : '上一首',
                      iconSize: 38,
                      onPressed:
                          busy || !capabilities.canPrevious ? null : onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    IconButton(
                      tooltip: '停止',
                      iconSize: 30,
                      onPressed: busy || !capabilities.canStop ? null : onStop,
                      icon: const Icon(Icons.stop_rounded),
                    ),
                    SizedBox(
                      width: compact ? 58 : 64,
                      height: compact ? 58 : 64,
                      child: IconButton.filled(
                        tooltip: status?.state == 'playing' ? '暂停' : '播放',
                        onPressed:
                            busy || !capabilities.canToggle ? null : onToggle,
                        iconSize: 34,
                        icon: Icon(
                          status?.state == 'playing'
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: isAudiobook ? '下一章' : '下一首',
                      iconSize: 38,
                      onPressed: busy || !capabilities.canNext ? null : onNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 4 : 8),
                if (status?.volume != null)
                  Row(
                    children: [
                      const Icon(Icons.volume_down),
                      Expanded(
                        child: Slider(
                          value: status!.volume!.toDouble().clamp(0, 100),
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: '${status!.volume}%',
                          onChanged: busy ? null : onVolumeChanged,
                        ),
                      ),
                      Text('${status!.volume}%'),
                    ],
                  ),
                const SizedBox(height: 0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _PlayerAction(
                      icon: isAudiobook ? Icons.list_alt : Icons.queue_music,
                      label: isAudiobook ? '章节' : '队列',
                      onTap: onOpenSource,
                    ),
                    _PlayerAction(
                      icon: Icons.cast,
                      label: '直链',
                      onTap: onPlayUrl,
                    ),
                    _PlayerAction(
                      icon: Icons.speaker,
                      label: '设备',
                      onTap: onOpenDevice,
                    ),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (diagnostic != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    diagnostic!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                if (operationMessage != null && diagnostic == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    operationMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.primary),
                  ),
                ],
              ],
            ),
          ),
        ),
          );
        },
      ),
    );
  }
}

class _SeekSlider extends StatefulWidget {
  const _SeekSlider({
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
  });

  final double position;
  final double duration;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _SeekSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragValue == null && oldWidget.position != widget.position) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.duration <= 0 ? 1.0 : widget.duration;
    final value = (_dragValue ?? widget.position).clamp(0, max).toDouble();
    return Slider(
      value: value,
      min: 0,
      max: max,
      onChanged: widget.enabled
          ? (next) => setState(() => _dragValue = next)
          : null,
      onChangeEnd: widget.enabled
          ? (next) {
              setState(() => _dragValue = null);
              widget.onSeek(next);
            }
          : null,
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.isAudiobook});
  final bool isAudiobook;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Center(
        child: Icon(
          isAudiobook ? Icons.auto_stories_rounded : Icons.graphic_eq_rounded,
          size: 104,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({
    required this.api,
    required this.device,
    required this.onPlayed,
    required this.onPlayLocal,
    required this.onOpenAudiobook,
    required this.onOpenDirectUrl,
  });

  final SongloftApi api;
  final SpeakerDevice? device;
  final VoidCallback onPlayed;
  final Future<void> Function(
    MediaItem song, {
    List<MediaItem> queue,
    int index,
  }) onPlayLocal;
  final VoidCallback onOpenAudiobook;
  final VoidCallback? onOpenDirectUrl;

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  final _query = TextEditingController();
  late Future<List<PlaylistSummary>> _playlists;
  PlaylistSummary? _selected;
  List<MediaItem> _songs = const [];
  bool _busy = false;
  String? _error;
  bool _showSources = false;

  @override
  void initState() {
    super.initState();
    _playlists = widget.api.getPlaylists();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylist(PlaylistSummary playlist) async {
    setState(() {
      _selected = playlist;
      _busy = true;
      _error = null;
    });
    try {
      final songs = await widget.api.getPlaylistSongs(playlist.id);
      if (mounted) setState(() => _songs = songs);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(MediaItem song, int index) async {
    final device = widget.device;
    final playlist = _selected;
    if (device == null || playlist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设备页面选择音箱')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (device.isLocal) {
        await widget.onPlayLocal(song, queue: _songs, index: index);
      } else {
        await widget.api.playPlaylist(
          device,
          playlist.id,
          startIndex: index,
          songId: song.id,
        );
        widget.onPlayed();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('正在播放：${song.title}')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSongMenu(MediaItem song, int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('立即播放'),
              onTap: () => Navigator.pop(context, 'play'),
            ),
            ListTile(
              leading: const Icon(Icons.speaker),
              title: const Text('投送到当前音箱'),
              subtitle: Text(widget.device?.name ?? '尚未选择设备'),
              onTap: () => Navigator.pop(context, 'play'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('歌曲信息'),
              subtitle: Text(song.subtitle.isEmpty ? '暂无更多信息' : song.subtitle),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (action == 'play') await _play(song, index);
  }

  Widget _buildSourceHub(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('统一音源入口', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('在同一处查看已接入的音乐、有声书和直链播放能力。', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _SourceCard(
          icon: Icons.library_music,
          title: 'Songloft 音乐',
          subtitle: '歌单、曲库与音箱播放控制',
          status: '已连接',
          color: scheme.primary,
          onTap: () => setState(() => _showSources = false),
        ),
        const SizedBox(height: 10),
        _SourceCard(
          icon: Icons.auto_stories,
          title: 'Audiobookshelf 有声书',
          subtitle: '书库、章节、继续收听与进度同步',
          status: '打开有声书',
          color: scheme.tertiary,
          onTap: widget.onOpenAudiobook,
        ),
        const SizedBox(height: 10),
        _SourceCard(
          icon: Icons.link,
          title: '音频直链',
          subtitle: '将 HTTP/HTTPS 音频地址投送到当前音箱',
          status: widget.onOpenDirectUrl == null ? '请先选择音箱' : '立即投送',
          color: scheme.secondary,
          onTap: widget.onOpenDirectUrl,
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.primary),
                const SizedBox(width: 12),
                const Expanded(child: Text('Subsonic、Navidrome 与 LXBridge 先保留为扩展位，待对应服务端接口接入后启用。')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistHub() {
    return FutureBuilder<List<PlaylistSummary>>(
      future: _playlists,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _playlists = widget.api.getPlaylists()),
          );
        }
        final playlists = snapshot.data ?? const [];
        if (playlists.isEmpty) {
          return const _EmptyState(icon: Icons.queue_music_outlined, title: '暂无可播放歌单', actionLabel: '重新加载');
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _playlists = widget.api.getPlaylists()),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final playlist = playlists[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.queue_music)),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songCount} 首歌曲'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _loadPlaylist(playlist),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _query.text.trim().toLowerCase();
    final visible = _songs
        .asMap()
        .entries
        .where((entry) {
          final song = entry.value;
          return keyword.isEmpty ||
              song.title.toLowerCase().contains(keyword) ||
              song.artist.toLowerCase().contains(keyword) ||
              song.album.toLowerCase().contains(keyword);
        })
        .toList();
    final page = Scaffold(
      appBar: AppBar(
        title: Text(_selected?.name ?? (_showSources ? '多音源' : '音乐')),
        leading: _selected == null
            ? null
            : IconButton(
                onPressed: () => setState(() {
                  _selected = null;
                  _songs = const [];
                  _query.clear();
                }),
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: _selected == null
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('曲库'), icon: Icon(Icons.library_music_outlined)),
                      ButtonSegment(value: true, label: Text('多音源'), icon: Icon(Icons.hub_outlined)),
                    ],
                    selected: {_showSources},
                    onSelectionChanged: (values) => setState(() => _showSources = values.first),
                  ),
                ),
                Expanded(child: _showSources ? _buildSourceHub(context) : _buildPlaylistHub()),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '搜索歌名、歌手或专辑',
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(_query.clear),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('没有匹配的歌曲'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, index) {
                            final entry = visible[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.music_note),
                              ),
                              title: Text(entry.value.title),
                              subtitle: Text(
                                entry.value.subtitle.isEmpty
                                    ? '未知歌手'
                                    : entry.value.subtitle,
                              ),
                              trailing: IconButton(
                                tooltip: '歌曲操作',
                                icon: const Icon(Icons.more_vert),
                                onPressed: _busy
                                    ? null
                                    : () => _showSongMenu(entry.value, entry.key),
                              ),
                              onTap: _busy
                                  ? null
                                  : () => _play(entry.value, entry.key),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
    if (_selected == null) return page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _selected = null;
            _songs = const [];
            _query.clear();
          });
        }
      },
      child: page,
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.icon, required this.title, required this.subtitle, required this.status, required this.color, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: .14), foregroundColor: color, child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Chip(label: Text(status), visualDensity: VisualDensity.compact),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.actionLabel});
  final IconData icon;
  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title),
          const SizedBox(height: 10),
          Text(actionLabel, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.config,
    required this.busy,
    required this.diagnostic,
    required this.onDiagnose,
    required this.onReconnect,
  });

  final ServerConfig config;
  final bool busy;
  final String? diagnostic;
  final VoidCallback onDiagnose;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Songloft'),
              subtitle: Text(config.normalizedBaseUrl),
            ),
          ),
          const SizedBox(height: 12),
          const Text('服务连接'),
          const SizedBox(height: 6),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.auto_stories_outlined),
                  title: Text('Audiobookshelf'),
                  subtitle: Text('在“有声书”页面管理连接与书库'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.speaker_outlined),
                  title: Text('MIoT 设备'),
                  subtitle: Text('在“设备”页面设置默认音箱并查看状态'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('播放与工具'),
          const SizedBox(height: 6),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('下载管理'),
                  subtitle: Text('等待 Songloft 下载接口接入'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.bedtime_outlined),
                  title: Text('睡眠定时'),
                  subtitle: Text('后续版本接入设备停止控制'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.speed),
                  title: Text('播放速度'),
                  subtitle: Text('取决于 MIoT 音箱能力'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: busy ? null : onDiagnose,
            icon: const Icon(Icons.health_and_safety_outlined),
            label: const Text('运行连接诊断'),
          ),
          if (diagnostic != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(diagnostic!),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onReconnect,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('更换账号或服务器'),
          ),
          const SizedBox(height: 24),
          const ListTile(
            title: Text('版本'),
            subtitle: Text('v0.7.0-alpha.1 播放内核重构预览版'),
          ),
        ],
      ),
    );
  }
}
