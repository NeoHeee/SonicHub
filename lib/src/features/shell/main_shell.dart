import 'package:flutter/material.dart';

import '../../core/models.dart';
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

  @override
  void initState() {
    super.initState();
    _devices = widget.api.getDevices();
  }

  Future<void> _refreshDevices() async {
    final future = widget.api.getDevices();
    setState(() => _devices = future);
    final devices = await future;
    if (!mounted) return;
    setState(() {
      if (devices.isEmpty) {
        _selectedDevice = null;
      } else if (_selectedDevice == null ||
          !devices.any((device) => device.id == _selectedDevice!.id)) {
        _selectedDevice = devices.first;
      }
    });
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
        devices: _devices,
        selectedDevice: _selectedDevice,
        status: _status,
        busy: _busy,
        onDeviceChanged: (device) {
          setState(() {
            _selectedDevice = device;
            _status = null;
          });
          _refreshStatus();
        },
        onRefresh: _refreshDevices,
        onRefreshStatus: _refreshStatus,
        onPlayUrl: _selectedDevice == null
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => UrlPlayerSheet(
                    api: widget.api,
                    device: _selectedDevice!,
                  ),
                ),
      ),
      _SearchPage(onOpenDirectUrl: () => setState(() => _index = 0)),
      SpeakersPage(api: widget.api),
      _SettingsPage(
        config: widget.config,
        busy: _busy,
        diagnostic: _diagnostic,
        onDiagnose: _diagnose,
        onReconnect: () => Navigator.of(context).pop(),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.speaker_outlined), selectedIcon: Icon(Icons.speaker), label: '设备'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.devices,
    required this.selectedDevice,
    required this.status,
    required this.busy,
    required this.onDeviceChanged,
    required this.onRefresh,
    required this.onRefreshStatus,
    required this.onPlayUrl,
  });

  final Future<List<SpeakerDevice>> devices;
  final SpeakerDevice? selectedDevice;
  final DeviceStatus? status;
  final bool busy;
  final ValueChanged<SpeakerDevice?> onDeviceChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onRefreshStatus;
  final VoidCallback? onPlayUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音枢 SonicHub')),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('智能音箱控制中心', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            FutureBuilder<List<SpeakerDevice>>(
              future: devices,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
                }
                if (snapshot.hasError) {
                  return Card(child: ListTile(leading: const Icon(Icons.cloud_off), title: Text(snapshot.error.toString()), trailing: IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh))));
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const Card(child: ListTile(leading: Icon(Icons.speaker_group_outlined), title: Text('没有找到可用音箱')));
                }
                final current = selectedDevice ?? items.first;
                if (selectedDevice == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => onDeviceChanged(current));
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<SpeakerDevice>(
                      value: items.any((item) => item.id == current.id) ? current : items.first,
                      decoration: const InputDecoration(labelText: '当前音箱', prefixIcon: Icon(Icons.speaker)),
                      items: [for (final item in items) DropdownMenuItem(value: item, child: Text(item.name))],
                      onChanged: onDeviceChanged,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.graphic_eq),
                      const SizedBox(width: 10),
                      Expanded(child: Text(status == null ? '尚未读取播放状态' : '状态：${status!.state}')),
                      IconButton(onPressed: selectedDevice == null || busy ? null : onRefreshStatus, icon: const Icon(Icons.refresh)),
                    ]),
                    if (status?.volume != null) Text('音量：${status!.volume}'),
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onPlayUrl, icon: const Icon(Icons.cast), label: const Text('推送音频直链')),
          ],
        ),
      ),
    );
  }
}

class _SearchPage extends StatelessWidget {
  const _SearchPage({required this.onOpenDirectUrl});
  final VoidCallback onOpenDirectUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TextField(enabled: false, decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: '多音源搜索将在接口确认后开放')),
          const SizedBox(height: 16),
          const Card(child: ListTile(leading: Icon(Icons.library_music_outlined), title: Text('Songloft 曲库与外部搜索'), subtitle: Text('下一批接入真实搜索结果和播放队列'))),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onOpenDirectUrl, icon: const Icon(Icons.link), label: const Text('先使用音频直链播放')),
        ],
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
          Card(child: ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('Songloft'), subtitle: Text(config.normalizedBaseUrl))),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(onPressed: busy ? null : onDiagnose, icon: const Icon(Icons.health_and_safety_outlined), label: const Text('运行连接诊断')),
          if (diagnostic != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(diagnostic!)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onReconnect, icon: const Icon(Icons.swap_horiz), label: const Text('更换服务器')),
          const SizedBox(height: 24),
          const ListTile(title: Text('版本'), subtitle: Text('0.2.0 测试版')),
        ],
      ),
    );
  }
}
