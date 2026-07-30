import 'package:flutter/material.dart';

import 'core/config_store.dart';
import 'core/server_config.dart';
import 'core/songloft_api.dart';
import 'features/shell/main_shell.dart';
import 'features/setup/setup_page.dart';

class SonicHubApp extends StatefulWidget {
  const SonicHubApp({super.key});

  @override
  State<SonicHubApp> createState() => _SonicHubAppState();
}

class _SonicHubAppState extends State<SonicHubApp> {
  late final Future<({SongloftApi api, ServerConfig config})?> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _restoreSession();
  }

  Future<({SongloftApi api, ServerConfig config})?> _restoreSession() async {
    final config = await ConfigStore().load();
    if (config == null) return null;

    final api = SongloftApi(config);
    try {
      await api.testConnection();
      return (api: api, config: config);
    } catch (_) {
      // 配置存在但服务暂时不可用时，回到连接页允许用户重试或修改配置。
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7157D9),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: '音枢 SonicHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F5FC),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: FutureBuilder<({SongloftApi api, ServerConfig config})?>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupPage();
          }
          final session = snapshot.data;
          if (session == null) {
            return SetupPage(configStore: ConfigStore());
          }
          return MainShell(api: session.api, config: session.config);
        },
      ),
    );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
