import 'package:flutter/material.dart';

import '../../core/config_store.dart';
import '../../core/server_config.dart';
import '../../core/songloft_api.dart';
import '../speakers/speakers_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({required this.configStore, super.key});

  final ConfigStore configStore;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.configStore.load().then((config) {
      if (!mounted || config == null) return;
      _url.text = config.baseUrl;
      _username.text = config.username;
      _password.text = config.password;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final config = ServerConfig(
      baseUrl: _url.text,
      username: _username.text.trim(),
      password: _password.text,
    );
    final api = SongloftApi(config);
    try {
      await api.testConnection();
      await widget.configStore.save(config);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SpeakersPage(api: api),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.hub_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '音枢 SonicHub',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '多音源智能音箱控制中心',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Songloft 服务地址',
                        hintText: 'http://192.168.1.10:58091',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      validator: (value) {
                        final uri = Uri.tryParse(value?.trim() ?? '');
                        return uri != null &&
                                (uri.scheme == 'http' || uri.scheme == 'https') &&
                                uri.host.isNotEmpty
                            ? null
                            : '请输入完整的 http:// 或 https:// 地址';
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? '请输入密码' : null,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(_busy ? '正在连接…' : '连接 Songloft'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '需要 Songloft 2.9.5+，并已安装和配置 MIoT 智能音箱插件。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
