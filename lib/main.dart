import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'screens/login_screen.dart';
import 'screens/video_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final dependencies = AppDependencies.create();
  runApp(VideoApp(dependencies: dependencies));
}

class VideoApp extends StatelessWidget {
  final AppDependencies dependencies;

  const VideoApp({
    super.key,
    required this.dependencies,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Platform MVP',
      theme: ThemeData.dark(useMaterial3: true),
      home: AppStartupScreen(dependencies: dependencies),
    );
  }
}

class AppStartupScreen extends StatefulWidget {
  final AppDependencies dependencies;

  const AppStartupScreen({
    super.key,
    required this.dependencies,
  });

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
    final token = await widget.dependencies.tokenStorage.getToken();
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

        return hasToken
            ? VideoListScreen(
                videoRepository: widget.dependencies.videoRepository,
                authRepository: widget.dependencies.authRepository,
                uploadRepository: widget.dependencies.uploadRepository,
                liveRepository: widget.dependencies.liveRepository,
              )
            : LoginScreen(
                authRepository: widget.dependencies.authRepository,
                videoRepository: widget.dependencies.videoRepository,
                uploadRepository: widget.dependencies.uploadRepository,
                liveRepository: widget.dependencies.liveRepository,
              );
      },
    );
  }
}