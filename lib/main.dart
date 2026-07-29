import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/background_agent_service.dart';
import 'services/notification_service.dart';
import 'ui/chat_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await initializeBackgroundService();
  await Permission.notification.request();
  runApp(const PagaiApp());
}

class PagaiApp extends StatelessWidget {
  const PagaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pagai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00E676),
      ),
      home: const ChatListPage(),
    );
  }
}
