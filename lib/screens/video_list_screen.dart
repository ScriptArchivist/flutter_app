import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../core/network/token_storage.dart';
import '../repositories/auth_repository.dart';
import '../repositories/video_repository.dart';
import 'live_screen.dart';
import 'login_screen.dart';
import 'upload_screen.dart';
import 'video_detail_screen.dart';

class VideoListScreen extends StatefulWidget {
  const VideoListScreen({super.key});

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  late final Dio dio;
  late final TokenStorage storage;
  late final VideoRepository videoRepository;
  late final AuthRepository authRepository;

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> videos = [];

  @override
  void initState() {
    super.initState();

    dio = Dio();
    storage = TokenStorage();
    ApiClient(dio, storage);

    videoRepository = VideoRepository(dio);
    authRepository = AuthRepository(dio, storage);

    loadVideos();
  }

  Future<void> loadVideos() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final result = await videoRepository.getVideos();

      if (!mounted) return;

      setState(() {
        videos = result;
        error = null;
        loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        error =
            e.response?.data?.toString() ?? e.message ?? 'Failed to load videos';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Failed to load videos: $e';
        loading = false;
      });
    }
  }

  Future<void> logout() async {
    await authRepository.logout();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String formatDuration(dynamic value) {
    if (value == null) return '—';
    if (value is! num) return value.toString();

    final seconds = value.round();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
    }

    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  String formatDateTime(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '—';

    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;

    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day.$month.$year $hour:$minute';
  }

  Future<void> openUpload() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UploadScreen()),
    );

    if (!mounted) return;
    await loadVideos();
  }

  Future<void> openLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LiveScreen()),
    );

    if (!mounted) return;
    await loadVideos();
  }

  Future<void> openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoDetailScreen(videoId: id)),
    );

    if (!mounted) return;
    await loadVideos();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error ?? 'Failed to load videos',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: loadVideos,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Список видео пуст'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: openUpload,
              child: const Text('Загрузить первое видео'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          IconButton(
            onPressed: openUpload,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload',
          ),
          IconButton(
            onPressed: openLive,
            icon: const Icon(Icons.live_tv),
            tooltip: 'Live',
          ),
          IconButton(
            onPressed: loading ? null : loadVideos,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _buildErrorState()
              : videos.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: loadVideos,
                      child: ListView.separated(
                        itemCount: videos.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final video = videos[index];
                          final id = video['id'];
                          final description =
                              video['description']?.toString().trim() ?? '';
                          final uploadedAt = formatDateTime(video['uploaded_at']);
                          final duration = formatDuration(video['duration']);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              video['title']?.toString().trim().isNotEmpty == true
                                  ? video['title'].toString()
                                  : 'Без названия',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(description),
                                ],
                                const SizedBox(height: 8),
                                Text('Добавлено: $uploadedAt'),
                                Text('Длительность: $duration'),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              final parsedId = id is int
                                  ? id
                                  : int.tryParse(id?.toString() ?? '');
                              if (parsedId != null) {
                                openDetail(parsedId);
                              }
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}