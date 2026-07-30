import 'package:flutter/material.dart';

import 'core/config_store.dart';
import 'features/setup/setup_page.dart';

class SonicHubApp extends StatelessWidget {
  const SonicHubApp({super.key});

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
      home: SetupPage(configStore: ConfigStore()),
    );
  }
}
