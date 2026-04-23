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

  bool _hasOwnerInfo(Map<String, dynamic> video) {
    final directCandidates = [
      video['owner_name'],
      video['created_by'],
      video['uploaded_by'],
      video['author'],
      video['username'],
    ];

    for (final candidate in directCandidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') {
        return true;
      }
    }

    final owner = video['owner'];
    if (owner is Map) {
      final nestedCandidates = [
        owner['name'],
        owner['username'],
        owner['login'],
        owner['email'],
      ];

      for (final candidate in nestedCandidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty && value != 'null') {
          return true;
        }
      }
    }

    final user = video['user'];
    if (user is Map) {
      final nestedCandidates = [
        user['name'],
        user['username'],
        user['login'],
        user['email'],
      ];

      for (final candidate in nestedCandidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty && value != 'null') {
          return true;
        }
      }
    }

    return false;
  }

  Future<List<Map<String, dynamic>>> _enrichVideosWithOwner(
    List<Map<String, dynamic>> items,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final item in items) {
      if (_hasOwnerInfo(item)) {
        result.add(item);
        continue;
      }

      final rawId = item['id'];
      final videoId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      if (videoId == null) {
        result.add(item);
        continue;
      }

      try {
        final detail = await videoRepository.getVideo(videoId);
        result.add({
          ...item,
          ...detail,
        });
      } catch (_) {
        result.add(item);
      }
    }

    return result;
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
      final enriched = await _enrichVideosWithOwner(result);

      if (!mounted) return;

      setState(() {
        videos = enriched;
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Логи очищены',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF121212),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ),
    );
  }

  void openLogsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            final logsEnabled = AppConfig.enableNetworkLogs;
            final logsText = logsEnabled
                ? (NetworkLogBuffer.text.isEmpty
                    ? 'Пока логов нет'
                    : NetworkLogBuffer.text)
                : 'Сетевое логирование отключено';

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.terminal, color: Colors.white70),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Логи приложения',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                            tooltip: 'Закрыть',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: logsEnabled
                                ? () async {
                                    await copyLogs();
                                    if (!mounted) return;
                                    modalSetState(() {});
                                  }
                                : null,
                            icon: const Icon(Icons.copy_all),
                            label: const Text('Копировать'),
                          ),
                          OutlinedButton.icon(
                            onPressed: logsEnabled
                                ? () {
                                    clearLogs();
                                    modalSetState(() {});
                                  }
                                : null,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Очистить'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              logsText,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Colors.white70,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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

  String _resolveThumbnail(Map<String, dynamic> video) {
    final primary = video['thumbnail_url']?.toString().trim();
    if (primary != null && primary.isNotEmpty) {
      return primary;
    }

    final candidates = [
      video['thumbnail'],
      video['thumb_url'],
      video['thumb'],
      video['preview_url'],
      video['preview'],
      video['image_url'],
      video['image'],
      video['poster_url'],
      video['poster'],
      video['cover_url'],
      video['cover'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  String _resolveOwner(Map<String, dynamic> video) {
    final directCandidates = [
      video['owner_name'],
      video['created_by'],
      video['uploaded_by'],
      video['author'],
      video['username'],
    ];

    for (final candidate in directCandidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    final owner = video['owner'];
    if (owner is Map) {
      final nestedCandidates = [
        owner['name'],
        owner['username'],
        owner['login'],
        owner['email'],
      ];

      for (final candidate in nestedCandidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty && value != 'null') {
          return value;
        }
      }
    }

    final user = video['user'];
    if (user is Map) {
      final nestedCandidates = [
        user['name'],
        user['username'],
        user['login'],
        user['email'],
      ];

      for (final candidate in nestedCandidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty && value != 'null') {
          return value;
        }
      }
    }

    return '—';
  }

  Widget _buildVideoThumbnail(Map<String, dynamic> video, String duration) {
    final thumbnailUrl = _resolveThumbnail(video);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 132,
        height: 78,
        color: Colors.white.withOpacity(0.06),
        child: Stack(
          children: [
            Positioned.fill(
              child: thumbnailUrl.isNotEmpty
                  ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const Center(
                          child: Icon(
                            Icons.video_library_outlined,
                            color: Colors.white54,
                            size: 28,
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.video_library_outlined,
                        color: Colors.white54,
                        size: 28,
                      ),
                    ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoItem(Map<String, dynamic> video) {
    final id = video['id'];
    final title = video['title']?.toString().trim();
    final description = video['description']?.toString().trim() ?? '';
    final uploadedAt = formatDateTime(video['uploaded_at']);
    final duration = formatDuration(video['duration']);
    final owner = _resolveOwner(video);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVideoThumbnail(video, duration),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title != null && title.isNotEmpty
                              ? title
                              : 'Без названия',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Добавлено: $uploadedAt',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Кем добавлено: $owner',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogsButton() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: openLogsSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.terminal,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppConfig.enableNetworkLogs
                          ? 'Логи приложения'
                          : 'Логи отключены',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/videos_background.png',
            fit: BoxFit.cover,
          ),
          Container(
            color: Colors.black.withOpacity(0.55),
          ),
          loading
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
                                        padding: const EdgeInsets.only(bottom: 84),
                                        itemCount: filtered.length,
                                        separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          color: Colors.white.withOpacity(0.06),
                                        ),
                                        itemBuilder: (context, index) {
                                          return _buildVideoItem(filtered[index]);
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
          _buildLogsButton(),
        ],
      ),
    );
  }
}