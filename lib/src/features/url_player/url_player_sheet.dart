import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/songloft_api.dart';

class UrlPlayerSheet extends StatefulWidget {
  const UrlPlayerSheet({
    required this.api,
    required this.device,
    required this.onPlayed,
    super.key,
  });

  final SongloftApi api;
  final SpeakerDevice device;
  final ValueChanged<String> onPlayed;

  @override
  State<UrlPlayerSheet> createState() => _UrlPlayerSheetState();
}

class _UrlPlayerSheetState extends State<UrlPlayerSheet> {
  final _url = TextEditingController();
  double _volume = 30;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.api.getStatus(widget.device).then((status) {
      if (mounted && status.volume != null) {
        setState(() => _volume = status.volume!.toDouble());
      }
    }).onError((_, __) {});
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.device.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '音频直链',
                  hintText: 'https://example.com/audio.mp3',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        final uri = Uri.tryParse(_url.text.trim());
                        if (uri == null ||
                            !uri.isAbsolute ||
                            !const ['http', 'https'].contains(uri.scheme)) {
                          setState(() => _message = '请输入有效的 HTTP/HTTPS 音频地址');
                          return;
                        }
                        _run(
                          () async {
                            await widget.api.playUrl(widget.device, uri.toString());
                            widget.onPlayed(uri.toString());
                          },
                          '已发送到音箱',
                        );
                      },
                icon: const Icon(Icons.cast_rounded),
                label: const Text('推送播放'),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.filledTonal(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => widget.api.pause(widget.device),
                              '已暂停',
                            ),
                    tooltip: '暂停',
                    icon: const Icon(Icons.pause),
                  ),
                  IconButton.filled(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => widget.api.resume(widget.device),
                              '已继续播放',
                            ),
                    tooltip: '继续',
                    icon: const Icon(Icons.play_arrow),
                  ),
                  IconButton.filledTonal(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => widget.api.stop(widget.device),
                              '已停止',
                            ),
                    tooltip: '停止',
                    icon: const Icon(Icons.stop),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.volume_down),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      max: 100,
                      divisions: 20,
                      label: _volume.round().toString(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _volume = value),
                      onChangeEnd: (value) => _run(
                        () => widget.api.setVolume(
                          widget.device,
                          value.round(),
                        ),
                        '音量已设为 ${value.round()}',
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, textAlign: TextAlign.center),
              ],
              if (_busy) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
