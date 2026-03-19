import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/error_parser.dart';
import '../repositories/auth_repository.dart';
import '../repositories/auth_state_controller.dart';
import '../repositories/live_repository.dart';
import '../repositories/upload_repository.dart';
import '../repositories/video_repository.dart';

class LoginScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final AuthStateController authStateController;
  final VideoRepository videoRepository;
  final UploadRepository uploadRepository;
  final LiveRepository liveRepository;

  const LoginScreen({
    super.key,
    required this.authRepository,
    required this.authStateController,
    required this.videoRepository,
    required this.uploadRepository,
    required this.liveRepository,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  String? error;

  AuthRepository get authRepository => widget.authRepository;
  AuthStateController get authStateController => widget.authStateController;

  bool get _networkLogsEnabled => AppConfig.enableNetworkLogs;

  @override
  void initState() {
    super.initState();

    if (_networkLogsEnabled) {
      NetworkLogBuffer.add(
        'APP CONFIG identityBaseUrl => ${AppConfig.identityBaseUrl}',
      );
      NetworkLogBuffer.add(
        'APP CONFIG identityLoginUrl => ${AppConfig.identityLoginUrl}',
      );
    }
  }

  Future<void> login() async {
    if (loading) return;

    final username = usernameController.text.trim();
    final password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        error = 'Введите username и password';
      });
      return;
    }

    if (!AppConfig.hasIdentityBaseUrl) {
      setState(() {
        error =
            'IDENTITY_BASE_URL пустой. APK, вероятно, собран без корректного --dart-define.';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    if (_networkLogsEnabled) {
      NetworkLogBuffer.add('LOGIN BUTTON PRESSED');
      NetworkLogBuffer.add('LOGIN SCREEN URL => ${AppConfig.identityLoginUrl}');
    }

    try {
      final token = await authRepository.login(username, password);
      await authStateController.setAuthenticated(token);

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = NetworkErrorMapper.map(
          e,
          fallbackMessage: 'Не удалось выполнить вход.',
          context: NetworkErrorContext.login,
        );
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prying Eye'),
        backgroundColor: Colors.black54,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/login_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Column(
                          children: [
                            const Spacer(flex: 2),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: usernameController,
                                    enabled: !loading,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Username',
                                      labelStyle: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Colors.white.withOpacity(0.25),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.08),
                                    ),
                                    textInputAction: TextInputAction.next,
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: passwordController,
                                    enabled: !loading,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      labelStyle: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Colors.white.withOpacity(0.25),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.08),
                                    ),
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => login(),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: loading ? null : login,
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: loading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Login'),
                                    ),
                                  ),
                                  if (error != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      error!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}