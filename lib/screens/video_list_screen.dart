import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/error_parser.dart';
import '../repositories/auth_repository.dart';
import '../repositories/auth_state_controller.dart';
import '../repositories/live_repository.dart';
import '../repositories/upload_repository.dart';
import '../repositories/video_repository.dart';
import 'live_lookup_screen.dart';
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
  bool showDebugLogs = false;
  String? error;
  List<Map<String, dynamic>> videos = [];
  String searchQuery = '';

  List<Map<String, dynamic>> get filteredVideos {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return videos;
    }

    return videos.where((video) {
      final title = video['title']?.toString().toLowerCase() ?? '';
      final description = video['description']?.toString().toLowerCase() ?? '';
      return title.contains(query) || description.contains(query);
    }).toList();
  }

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

  Future<void> copyLogs() async {
    if (!AppConfig.enableNetworkLogs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сетевое логирование отключено')),
      );
      return;
    }

    final text = NetworkLogBuffer.text;

    await Clipboard.setData(
      ClipboardData(
        text: text.isEmpty ? 'Пока логов нет' : text,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Логи скопированы')),
    );
  }

  void clearLogs() {
    if (!AppConfig.enableNetworkLogs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сетевое логирование отключено')),
      );
      return;
    }

    setState(() {
      NetworkLogBuffer.clear();
    });
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

  Future<void> openLiveProducer() async {
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

  Future<void> openLiveViewer() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveLookupScreen(
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

  Widget _buildSearchEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('По вашему запросу ничего не найдено'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  searchQuery = '';
                });
              },
              child: const Text('Сбросить поиск'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Поиск по видео',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          suffixIcon: searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    setState(() {
                      searchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.clear, color: Colors.white70),
                  tooltip: 'Очистить',
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
        style: const TextStyle(color: Colors.white),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildDebugLogs() {
    final logs = NetworkLogBuffer.text;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        initiallyExpanded: showDebugLogs,
        onExpansionChanged: (value) {
          setState(() {
            showDebugLogs = value;
          });
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text(
          'Debug logs',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          AppConfig.enableNetworkLogs
              ? 'Сетевое логирование включено'
              : 'Сетевое логирование отключено',
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: AppConfig.enableNetworkLogs ? copyLogs : null,
                  child: const Text('Скопировать логи'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: AppConfig.enableNetworkLogs ? clearLogs : null,
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
              AppConfig.enableNetworkLogs
                  ? (logs.isEmpty ? 'Пока логов нет' : logs)
                  : 'Сетевое логирование отключено для этой сборки',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredVideos;

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
            onPressed: openLiveProducer,
            icon: const Icon(Icons.videocam),
            tooltip: 'Live producer',
          ),
          IconButton(
            onPressed: openLiveViewer,
            icon: const Icon(Icons.live_tv),
            tooltip: 'Live viewer',
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
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: _buildSearchField(),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? _buildSearchEmptyState()
                              : RefreshIndicator(
                                  onRefresh: loadVideos,
                                  child: ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final video = filtered[index];
                                      final id = video['id'];
                                      final description = video['description']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final uploadedAt =
                                          formatDateTime(video['uploaded_at']);
                                      final duration =
                                          formatDuration(video['duration']);

                                      return ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        title: Text(
                                          video['title']
                                                      ?.toString()
                                                      .trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? video['title'].toString()
                                              : 'Без названия',
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                        trailing:
                                            const Icon(Icons.chevron_right),
                                        onTap: () {
                                          final parsedId = id is int
                                              ? id
                                              : int.tryParse(
                                                  id?.toString() ?? '',
                                                );
                                          if (parsedId != null) {
                                            openDetail(parsedId);
                                          }
                                        },
                                      );
                                    },
                                  ),
                                ),
                        ),
                        _buildDebugLogs(),
                      ],
                    ),
    );
  }
}