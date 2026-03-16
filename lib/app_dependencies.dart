import 'package:dio/dio.dart';

import 'core/network/api_client.dart';
import 'core/network/token_storage.dart';
import 'repositories/auth_repository.dart';
import 'repositories/auth_state_controller.dart';
import 'repositories/live_repository.dart';
import 'repositories/upload_repository.dart';
import 'repositories/video_repository.dart';

class AppDependencies {
  final Dio dio;
  final TokenStorage tokenStorage;
  final ApiClient apiClient;
  final AuthRepository authRepository;
  final AuthStateController authStateController;
  final LiveRepository liveRepository;
  final UploadRepository uploadRepository;
  final VideoRepository videoRepository;

  AppDependencies._({
    required this.dio,
    required this.tokenStorage,
    required this.apiClient,
    required this.authRepository,
    required this.authStateController,
    required this.liveRepository,
    required this.uploadRepository,
    required this.videoRepository,
  });

  factory AppDependencies.create() {
    final dio = Dio();
    final tokenStorage = TokenStorage();
    final authStateController = AuthStateController(tokenStorage);

    final apiClient = ApiClient(
      dio,
      tokenStorage,
      onUnauthorized: authStateController.handleUnauthorized,
    );

    final authRepository = AuthRepository(dio, tokenStorage);
    final liveRepository = LiveRepository(dio);
    final uploadRepository = UploadRepository(dio);
    final videoRepository = VideoRepository(dio);

    return AppDependencies._(
      dio: dio,
      tokenStorage: tokenStorage,
      apiClient: apiClient,
      authRepository: authRepository,
      authStateController: authStateController,
      liveRepository: liveRepository,
      uploadRepository: uploadRepository,
      videoRepository: videoRepository,
    );
  }
}