import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/library_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const ProviderScope(child: PaperSyncApp()));
}

class PaperSyncApp extends StatelessWidget {
  const PaperSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const LibraryScreen(),
    );
  }
}
