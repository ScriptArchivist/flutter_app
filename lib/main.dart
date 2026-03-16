import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'repositories/auth_state_controller.dart';
import 'screens/login_screen.dart';
import 'screens/video_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final dependencies = AppDependencies.create();
  runApp(VideoApp(dependencies: dependencies));
}

class VideoApp extends StatefulWidget {
  final AppDependencies dependencies;

  const VideoApp({
    super.key,
    required this.dependencies,
  });

  @override
  State<VideoApp> createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  AuthStatus? _lastHandledStatus;

  @override
  void initState() {
    super.initState();
    widget.dependencies.authStateController.addListener(_handleAuthStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.dependencies.authStateController.init();
      _handleAuthStateChanged();
    });
  }

  @override
  void dispose() {
    widget.dependencies.authStateController.removeListener(
      _handleAuthStateChanged,
    );
    super.dispose();
  }

  void _handleAuthStateChanged() {
    if (!mounted) {
      return;
    }

    final status = widget.dependencies.authStateController.status;

    if (status == AuthStatus.unknown) {
      return;
    }

    if (_lastHandledStatus == status) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAuthStateChanged();
      });
      return;
    }

    _lastHandledStatus = status;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) {
          if (status == AuthStatus.authenticated) {
            return VideoListScreen(
              videoRepository: widget.dependencies.videoRepository,
              authRepository: widget.dependencies.authRepository,
              authStateController: widget.dependencies.authStateController,
              uploadRepository: widget.dependencies.uploadRepository,
              liveRepository: widget.dependencies.liveRepository,
            );
          }

          return LoginScreen(
            authRepository: widget.dependencies.authRepository,
            authStateController: widget.dependencies.authStateController,
            videoRepository: widget.dependencies.videoRepository,
            uploadRepository: widget.dependencies.uploadRepository,
            liveRepository: widget.dependencies.liveRepository,
          );
        },
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Platform MVP',
      theme: ThemeData.dark(useMaterial3: true),
      navigatorKey: _navigatorKey,
      home: const _SplashScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}