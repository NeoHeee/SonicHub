import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/songloft_api.dart';

class SpeakersPage extends StatelessWidget {
  const SpeakersPage({
    required this.devices,
    required this.api,
    required this.selectedDevice,
    required this.onSelected,
    required this.onRefresh,
    super.key,
  });

  final Future<List<SpeakerDevice>> devices;
  final SongloftApi api;
  final SpeakerDevice? selectedDevice;
  final ValueChanged<SpeakerDevice> onSelected;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备'),
        actions: [
          IconButton(
            onPressed: onRefresh,
            tooltip: '刷新设备',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<SpeakerDevice>>(
        future: devices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.cloud_off_outlined,
              text: snapshot.error.toString(),
              action: onRefresh,
            );
          }
          final items = [SpeakerDevice.local, ...?snapshot.data];
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final device = items[index];
                final selected = device.id == selectedDevice?.id &&
                    device.accountId == selectedDevice?.accountId;
                return Card(
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      child: Icon(
                        device.isLocal
                            ? (selected ? Icons.phone_android : Icons.phone_android_outlined)
                            : (selected ? Icons.speaker : Icons.speaker_outlined),
                      ),
                    ),
                    title: Text(device.name),
                    subtitle: Text([
                      device.isLocal ? '手机扬声器 / 蓝牙设备' : (device.model ?? '智能音箱'),
                      if (selected) device.isLocal ? '当前播放设备' : '默认输出设备',
                    ].join(' · ')),
                    trailing: selected
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.radio_button_unchecked),
                    onTap: () => onSelected(device),
                    onLongPress: () => device.isLocal
                        ? _showLocalDetail(context, selected)
                        : _showDeviceDetail(context, device, selected),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDeviceDetail(
    BuildContext context,
    SpeakerDevice device,
    bool selected,
  ) async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _DeviceDetailSheet(
        api: api,
        device: device,
        selected: selected,
        onUse: () {
          onSelected(device);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  void _showLocalDetail(BuildContext context, bool selected) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Icon(Icons.phone_android)),
                title: Text('本机播放'),
                subtitle: Text('直接使用当前设备扬声器或已连接的蓝牙设备'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: selected
                    ? null
                    : () {
                        onSelected(SpeakerDevice.local);
                        Navigator.pop(sheetContext);
                      },
                icon: const Icon(Icons.check_circle_outline),
                label: Text(selected ? '当前播放设备' : '使用本机播放'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceDetailSheet extends StatefulWidget {
  const _DeviceDetailSheet({
    required this.api,
    required this.device,
    required this.selected,
    required this.onUse,
  });
  final SongloftApi api;
  final SpeakerDevice device;
  final bool selected;
  final VoidCallback onUse;

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  late Future<DeviceStatus> _status = widget.api.getStatus(widget.device);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.speaker)),
              title: Text(widget.device.name),
              subtitle: Text(widget.device.model ?? '智能音箱'),
              trailing: IconButton(
                tooltip: '刷新状态',
                onPressed: () => setState(
                  () => _status = widget.api.getStatus(widget.device),
                ),
                icon: const Icon(Icons.refresh),
              ),
            ),
            FutureBuilder<DeviceStatus>(
              future: _status,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _Message(
                    icon: Icons.cloud_off_outlined,
                    text: '状态读取失败：${snapshot.error}',
                    action: () async => setState(
                      () => _status = widget.api.getStatus(widget.device),
                    ),
                  );
                }
                final status = snapshot.data!;
                return Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          status.state == 'playing'
                              ? Icons.play_circle
                              : Icons.pause_circle_outline,
                        ),
                        title: Text(status.currentSong?.title ?? '暂无播放内容'),
                        subtitle: Text('状态：${status.state}'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.volume_up_outlined),
                        title: const Text('当前音量'),
                        trailing: Text(status.volume == null
                            ? '未知'
                            : '${status.volume}%'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.selected ? null : widget.onUse,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(widget.selected ? '当前默认音箱' : '设为默认音箱'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String text;
  final Future<void> Function() action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: action, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
