import 'package:flutter/material.dart';

import '../../core/models.dart';

class SpeakersPage extends StatelessWidget {
  const SpeakersPage({
    required this.devices,
    required this.selectedDevice,
    required this.onSelected,
    required this.onRefresh,
    super.key,
  });

  final Future<List<SpeakerDevice>> devices;
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
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return _Message(
              icon: Icons.speaker_group_outlined,
              text: '没有找到音箱，请先在 MIoT 插件中添加账号并启用设备。',
              action: onRefresh,
            );
          }
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
                      child: Icon(selected ? Icons.speaker : Icons.speaker_outlined),
                    ),
                    title: Text(device.name),
                    subtitle: Text(device.model ?? '智能音箱'),
                    trailing: selected
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.radio_button_unchecked),
                    onTap: () => onSelected(device),
                  ),
                );
              },
            ),
          );
        },
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
