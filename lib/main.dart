import 'package:flutter/material.dart';

import 'core/network/token_storage.dart';
import 'screens/login_screen.dart';
import 'screens/video_list_screen.dart';

void main() {
  runApp(const VideoApp());
}

class VideoApp extends StatelessWidget {
  const VideoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Platform MVP',
      theme: ThemeData.dark(useMaterial3: true),
      home: const AppStartupScreen(),
    );
  }
}

class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  late final Future<bool> _hasTokenFuture;

  @override
  void initState() {
    super.initState();
    _hasTokenFuture = _hasToken();
  }

  Future<bool> _hasToken() async {
    final storage = TokenStorage();
    final token = await storage.getToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasTokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final hasToken = snapshot.data == true;
        return hasToken ? VideoListScreen() : const LoginScreen();
      },
    );
  }
}