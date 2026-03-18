import 'package:flutter/material.dart';

import '../core/network/error_parser.dart';
import '../repositories/auth_repository.dart';
import '../repositories/auth_state_controller.dart';
import '../repositories/live_repository.dart';
import '../repositories/upload_repository.dart';
import '../repositories/video_repository.dart';
import 'live_screen.dart';
import 'upload_screen.dart';
import 'video_detail_screen.dart';

class VideoListScreen extends StatefulWidget {
  final VideoRepository videoRepository;
  final AuthRepository authRepository;
  final AuthStateController authStateController;
  final UploadRepository uploadRepository;
  final LiveRepository liveRepository;

  const VideoListScreen({
    super.key,
    required this.videoRepository,
    required this.authRepository,
    required this.authStateController,
    required this.uploadRepository,
    required this.liveRepository,
  });

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  VideoRepository get videoRepository => widget.videoRepository;
  AuthRepository get authRepository => widget.authRepository;
  AuthStateController get authStateController => widget.authStateController;
  UploadRepository get uploadRepository => widget.uploadRepository;
  LiveRepository get liveRepository => widget.liveRepository;

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> videos = [];

  @override
  void initState() {
    super.initState();
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
    } catch (e) {
      if (!mounted) return;

      if (NetworkErrorMapper.isUnauthorized(e)) {
        setState(() {
          loading = false;
        });
        return;
      }

      setState(() {
        error = NetworkErrorMapper.map(
          e,
          fallbackMessage: 'Не удалось загрузить список видео.',
        );
        loading = false;
      });
    }
  }

  Future<void> logout() async {
    await authStateController.logout();
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
      MaterialPageRoute(
        builder: (_) => UploadScreen(
          videoRepository: videoRepository,
          uploadRepository: uploadRepository,
        ),
      ),
    );

    if (!mounted) return;
    await loadVideos();
  }

  Future<void> openLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveScreen(
          liveRepository: liveRepository,
        ),
      ),
    );

    if (!mounted) return;
    await loadVideos();
  }

  Future<void> openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailScreen(
          videoId: id,
          videoRepository: videoRepository,
        ),
      ),
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
                          final uploadedAt =
                              formatDateTime(video['uploaded_at']);
                          final duration = formatDuration(video['duration']);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              video['title']?.toString().trim().isNotEmpty ==
                                      true
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