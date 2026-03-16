import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/token_storage.dart';
import '../repositories/auth_repository.dart';
import 'video_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool showDebugLogs = false;
  String? error;

  late final AuthRepository authRepository;

  @override
  void initState() {
    super.initState();

    final dio = Dio();
    final storage = TokenStorage();

    ApiClient(dio, storage);
    authRepository = AuthRepository(dio, storage);

    NetworkLogBuffer.add(
      'APP CONFIG identityBaseUrl => ${AppConfig.identityBaseUrl}',
    );
    NetworkLogBuffer.add(
      'APP CONFIG identityLoginUrl => ${AppConfig.identityLoginUrl}',
    );
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

    NetworkLogBuffer.add('LOGIN BUTTON PRESSED');
    NetworkLogBuffer.add('LOGIN SCREEN URL => ${AppConfig.identityLoginUrl}');

    try {
      await authRepository.login(username, password);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VideoListScreen(),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;

      String message = 'Login failed';
      final data = e.response?.data;

      if (data is Map) {
        final map = Map<String, dynamic>.from(data);

        if (map['error'] is Map) {
          final err = Map<String, dynamic>.from(map['error'] as Map);
          message = (err['message'] ?? err['code'] ?? message).toString();
        } else if (map['detail'] != null) {
          message = map['detail'].toString();
        } else if (map['message'] != null) {
          message = map['message'].toString();
        }
      } else if (e.response?.statusCode == 401) {
        message = 'Неверный username или password';
      } else if (e.message != null && e.message!.isNotEmpty) {
        message = e.message!;
      }

      setState(() {
        error = message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'Login failed: $e';
        loading = false;
      });
    }
  }

  void copyLogs() {
    final text = [
      'IDENTITY_BASE_URL: ${AppConfig.identityBaseUrl}',
      'LOGIN URL: ${AppConfig.identityLoginUrl}',
      '',
      'NETWORK LOGS:',
      NetworkLogBuffer.text,
    ].join('\n');

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Логи скопированы')),
    );
  }

  void clearLogs() {
    setState(() {
      NetworkLogBuffer.clear();
    });
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = NetworkLogBuffer.text;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prying Eye'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF1F2A44),
                        Color(0xFF243B55),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.videocam_rounded,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Добро пожаловать',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Войдите, чтобы просматривать видео, загружать записи и запускать трансляции.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: usernameController,
                  enabled: !loading,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  enabled: !loading,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
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
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Text('Login'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                ExpansionTile(
                  initiallyExpanded: showDebugLogs,
                  onExpansionChanged: (value) {
                    setState(() {
                      showDebugLogs = value;
                    });
                  },
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text(
                    'Debug logs',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: copyLogs,
                            child: const Text('Скопировать логи'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: clearLogs,
                            child: const Text('Очистить логи'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 180),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        logs.isEmpty ? 'Пока логов нет' : logs,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}