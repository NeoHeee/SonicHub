import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audiobookshelf_api.dart';
import '../../core/config_store.dart';
import '../../core/models.dart';
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
  SpeakerDevice? _selectedDevice;
  DeviceStatus? _status;
  String? _diagnostic;
  bool _busy = false;
  String? _externalTitle;
  String? _externalSubtitle;
  String? _externalSource;
  String? _externalCoverUrl;
  Future<void> Function()? _audiobookNext;
  final _configStore = ConfigStore();

  @override
  void initState() {
    super.initState();
    _devices = _loadDevices();
  }

  Future<List<SpeakerDevice>> _loadDevices() async {
    final devices = await widget.api.getDevices();
    final saved = await _configStore.loadSelectedDevice();
    if (devices.isNotEmpty && _selectedDevice == null) {
      final selected = saved == null
          ? devices.first
          : devices.firstWhere(
              (item) =>
                  item.id == saved.deviceId &&
                  item.accountId == saved.accountId,
              orElse: () => devices.first,
            );
      if (mounted) setState(() => _selectedDevice = selected);
      await _refreshStatus();
    }
    return devices;
  }

  Future<void> _refreshDevices() async {
    final future = _loadDevices();
    setState(() => _devices = future);
    try {
      final devices = await future;
      if (!mounted) return;
      final selectedId = _selectedDevice?.id;
      final selectedAccountId = _selectedDevice?.accountId;
      setState(() {
        _selectedDevice = devices.isEmpty
            ? null
            : devices.firstWhere(
                (item) =>
                    item.id == selectedId &&
                    item.accountId == selectedAccountId,
                orElse: () => devices.first,
              );
      });
      await _refreshStatus();
    } catch (_) {}
  }

  Future<void> _selectDevice(SpeakerDevice? device) async {
    setState(() {
      _selectedDevice = device;
      _status = null;
      _externalTitle = null;
      _externalSubtitle = null;
      _externalSource = null;
      _externalCoverUrl = null;
      _audiobookNext = null;
    });
    if (device != null) {
      await _configStore.saveSelectedDevice(device.accountId, device.id);
    }
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final device = _selectedDevice;
    if (device == null) return;
    setState(() {
      _busy = true;
      _diagnostic = null;
    });
    try {
      final status = await widget.api.getStatus(device);
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _diagnostic = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _control(Future<void> Function(SpeakerDevice) action) async {
    final device = _selectedDevice;
    if (device == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(device);
      await _refreshStatus();
    } catch (error) {
      if (mounted) {
        setState(() => _diagnostic = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setVolume(double value) async {
    await _control((device) => widget.api.setVolume(device, value.round()));
  }

  void _showAudiobook(
    AbsBook book,
    String? chapterTitle,
    String? coverUrl,
    Future<void> Function() onNext,
  ) {
    setState(() {
      _externalTitle = book.title;
      _externalSubtitle = [
        if (chapterTitle?.trim().isNotEmpty == true) chapterTitle!.trim(),
        if (book.subtitle.trim().isNotEmpty) book.subtitle.trim(),
      ].join(' · ');
      _externalSource = 'Audiobookshelf';
      _externalCoverUrl = coverUrl;
      _audiobookNext = onNext;
    });
    _refreshStatus();
  }

  void _clearExternalPlayback() {
    setState(() {
      _externalTitle = null;
      _externalSubtitle = null;
      _externalSource = null;
      _externalCoverUrl = null;
      _audiobookNext = null;
    });
    _refreshStatus();
  }

  Future<void> _next() async {
    final audiobookNext = _audiobookNext;
    if (_externalSource != 'Audiobookshelf' || audiobookNext == null) {
      await _control(widget.api.next);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await audiobookNext();
      await _refreshStatus();
    } catch (error) {
      if (mounted) {
        setState(() => _diagnostic = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  Future<void> _diagnose() async {
    setState(() {
      _busy = true;
      _diagnostic = null;
    });
    try {
      await widget.api.testConnection();
      final devices = await widget.api.getDevices();
      if (!mounted) return;
      setState(() {
        _diagnostic = devices.isEmpty
            ? 'Songloft 已连接，但 MIoT 插件没有返回音箱。'
            : '连接正常，MIoT 插件返回 ${devices.length} 台音箱。';
      });
    } catch (error) {
      if (mounted) setState(() => _diagnostic = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(
        selectedDevice: _selectedDevice,
        status: _status,
        busy: _busy,
        diagnostic: _diagnostic,
        onRefresh: _refreshStatus,
        onRefreshStatus: _refreshStatus,
        onPrevious: () => _control(widget.api.previous),
        onToggle: () => _control(widget.api.togglePlayback),
        onNext: _next,
        onVolumeChanged: _setVolume,
        externalTitle: _externalTitle,
        externalSubtitle: _externalSubtitle,
        externalSource: _externalSource,
        externalCoverUrl: _externalCoverUrl,
        onOpenDevice: () => setState(() => _index = 3),
        onOpenSource: () => setState(() => _index = _externalSource == 'Audiobookshelf' ? 2 : 1),
        onPlayUrl: _selectedDevice == null
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => UrlPlayerSheet(
                    api: widget.api,
                    device: _selectedDevice!,
                  ),
                ).then((_) => _clearExternalPlayback()),
      ),
      _LibraryPage(
        api: widget.api,
        device: _selectedDevice,
        onPlayed: _clearExternalPlayback,
      ),
      AudiobookshelfPage(
        songloftApi: widget.api,
        device: _selectedDevice,
        onPlayed: _showAudiobook,
      ),
      SpeakersPage(
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
            label: '首页',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
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
            label: '设置',
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
    required this.busy,
    required this.diagnostic,
    required this.onRefresh,
    required this.onRefreshStatus,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onVolumeChanged,
    required this.externalTitle,
    required this.externalSubtitle,
    required this.externalSource,
    required this.externalCoverUrl,
    required this.onOpenDevice,
    required this.onOpenSource,
    required this.onPlayUrl,
  });

  final SpeakerDevice? selectedDevice;
  final DeviceStatus? status;
  final bool busy;
  final String? diagnostic;
  final Future<void> Function() onRefresh;
  final VoidCallback onRefreshStatus;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final ValueChanged<double> onVolumeChanged;
  final String? externalTitle;
  final String? externalSubtitle;
  final String? externalSource;
  final String? externalCoverUrl;
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
    final isAudiobook = externalSource == 'Audiobookshelf';
    final title = externalTitle ?? song?.title ?? '暂无播放内容';
    final subtitle = externalSubtitle ??
        (song?.subtitle.isNotEmpty == true
            ? song!.subtitle
            : (status?.playlistName.isNotEmpty == true
                ? status!.playlistName
                : '从曲库或有声书中选择内容'));
    final coverUrl = isAudiobook ? externalCoverUrl : song?.coverUrl;
    final duration = status?.duration ?? 0;
    final position = status?.position ?? 0;
    final progress = duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);

    return Scaffold(
      body: RefreshIndicator(
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
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
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
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: AspectRatio(
                      aspectRatio: isAudiobook ? 0.78 : 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 30,
                                offset: Offset(0, 16),
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
                const SizedBox(height: 30),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Chip(
                    avatar: Icon(
                      isAudiobook ? Icons.auto_stories : Icons.library_music,
                      size: 18,
                    ),
                    label: Text(isAudiobook ? 'Audiobookshelf · 有声书' : 'Songloft · 音乐'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 20),
                Slider(value: progress, onChanged: null),
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
                    '章节播放 · 进度自动回传',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: isAudiobook ? '上一章' : '上一首',
                      iconSize: 38,
                      onPressed: selectedDevice == null || busy ? null : onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: IconButton.filled(
                        tooltip: status?.state == 'playing' ? '暂停' : '播放',
                        onPressed: selectedDevice == null || busy ? null : onToggle,
                        iconSize: 42,
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
                      onPressed: selectedDevice == null || busy ? null : onNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 6),
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
              ],
            ),
          ),
        ),
      ),
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
  });

  final SongloftApi api;
  final SpeakerDevice? device;
  final VoidCallback onPlayed;

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
        const SnackBar(content: Text('请先在首页选择音箱')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.playPlaylist(
        device,
        playlist.id,
        startIndex: index,
        songId: song.id,
      );
      widget.onPlayed();
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
        title: Text(_selected?.name ?? '曲库与歌单'),
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
          ? FutureBuilder<List<PlaylistSummary>>(
              future: _playlists,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(
                    message: snapshot.error.toString(),
                    onRetry: () => setState(
                      () => _playlists = widget.api.getPlaylists(),
                    ),
                  );
                }
                final playlists = snapshot.data ?? const [];
                if (playlists.isEmpty) {
                  return const Center(child: Text('暂无可播放歌单'));
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(
                    () => _playlists = widget.api.getPlaylists(),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: playlists.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final playlist = playlists[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.queue_music),
                          title: Text(playlist.name),
                          subtitle: Text('${playlist.songCount} 首'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _loadPlaylist(playlist),
                        ),
                      );
                    },
                  ),
                );
              },
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
                              trailing: const Icon(Icons.play_arrow),
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
      appBar: AppBar(title: const Text('设置')),
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
            subtitle: Text('0.3.2 测试版'),
          ),
        ],
      ),
    );
  }
}
