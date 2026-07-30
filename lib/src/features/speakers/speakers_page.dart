import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/songloft_api.dart';
import '../url_player/url_player_sheet.dart';

class SpeakersPage extends StatefulWidget {
  const SpeakersPage({required this.api, super.key});
  final SongloftApi api;

  @override
  State<SpeakersPage> createState() => _SpeakersPageState();
}

class _SpeakersPageState extends State<SpeakersPage> {
  late Future<List<SpeakerDevice>> _devices;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final devices = widget.api.getDevices();
    setState(() {
      _devices = devices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择音箱'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: '刷新设备',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<SpeakerDevice>>(
        future: _devices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.cloud_off_outlined,
              text: snapshot.error.toString(),
              action: _reload,
            );
          }
          final devices = snapshot.data ?? const [];
          if (devices.isEmpty) {
            return _Message(
              icon: Icons.speaker_group_outlined,
              text: '没有找到音箱，请先在 MIoT 插件中添加账号并启用设备。',
              action: _reload,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: const CircleAvatar(
                    child: Icon(Icons.speaker_rounded),
                  ),
                  title: Text(device.name),
                  subtitle: Text(device.model ?? '智能音箱'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => UrlPlayerSheet(
                      api: widget.api,
                      device: device,
                    ),
                  ),
                ),
              );
            },
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
  final VoidCallback action;

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
