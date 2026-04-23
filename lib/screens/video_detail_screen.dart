import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../repositories/video_repository.dart';
import '../widgets/hls_player.dart';

class VideoDetailScreen extends StatefulWidget {
  final int videoId;
  final VideoRepository videoRepository;

  const VideoDetailScreen({
    super.key,
    required this.videoId,
    required this.videoRepository,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  VideoRepository get videoRepository => widget.videoRepository;

  static const Color _titleColor = Color(0xFFEAF1FF);
  static const Color _primaryTextColor = Color(0xFFD8E0F0);
  static const Color _secondaryTextColor = Color(0xFF9CA8BF);
  static const Color _surfaceColor = Color(0xFF131A24);
  static const Color _surfaceBorderColor = Color(0x1AFFFFFF);

  bool loading = true;
  bool actionLoading = false;
  String? error;
  Map<String, dynamic>? video;
  Map<String, dynamic>? playback;
  Timer? pollingTimer;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    loadVideo();
  }

  Future<void> loadVideo() async {
    if (_requestInFlight) return;
    _requestInFlight = true;

    try {
      final detail = await videoRepository.getVideo(
        widget.videoId,
        consistent: true,
      );

      Map<String, dynamic>? playbackData;

      final status = detail['status']?.toString();
      final hlsReady = detail['hls_ready'] == true;

      if (status == 'ready' || hlsReady) {
        playbackData = await videoRepository.getPlayback(
          widget.videoId,
          consistent: true,
        );
      }

      if (!mounted) return;

      setState(() {
        video = detail;
        playback = playbackData;
        error = null;
        loading = false;
      });

      _configurePolling(status);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        error =
            e.response?.data?.toString() ?? e.message ?? 'Failed to load video';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Failed to load video: $e';
        loading = false;
      });
    } finally {
      _requestInFlight = false;
    }
  }

  void _configurePolling(String? status) {
    final shouldPoll =
        status == 'uploading' ||
        status == 'uploaded' ||
        status == 'processing';

    if (!shouldPoll) {
      pollingTimer?.cancel();
      pollingTimer = null;
      return;
    }

    if (pollingTimer != null && pollingTimer!.isActive) {
      return;
    }

    pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => loadVideo(),
    );
  }

  Future<void> editVideo() async {
    final currentVideo = video;
    if (currentVideo == null || actionLoading) return;

    final titleController = TextEditingController(
      text: currentVideo['title']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: currentVideo['description']?.toString() ?? '',
    );
    String selectedVisibility =
        currentVideo['visibility']?.toString() ?? 'private';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171E29),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          title: const Text(
            'Edit video',
            style: TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Title',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      style: const TextStyle(color: Colors.white),
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedVisibility,
                      dropdownColor: const Color(0xFF171E29),
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(
                          value: 'private',
                          child: Text('private'),
                        ),
                        DropdownMenuItem(
                          value: 'public',
                          child: Text('public'),
                        ),
                        DropdownMenuItem(
                          value: 'unlisted',
                          child: Text('unlisted'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() {
                            selectedVisibility = value;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Visibility',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'title': titleController.text.trim(),
                  'description': descriptionController.text,
                  'visibility': selectedVisibility,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C91FF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    descriptionController.dispose();

    if (result == null) return;

    final currentTitle = currentVideo['title']?.toString() ?? '';
    final currentDescription = currentVideo['description']?.toString() ?? '';
    final currentVisibility =
        currentVideo['visibility']?.toString() ?? 'private';

    final newTitle = result['title']?.toString() ?? '';
    final newDescription = result['description']?.toString() ?? '';
    final newVisibility =
        result['visibility']?.toString() ?? currentVisibility;

    final payload = <String, dynamic>{};

    if (newTitle != currentTitle) {
      payload['title'] = newTitle;
    }

    if (newDescription != currentDescription) {
      payload['description'] = newDescription;
    }

    if (newVisibility != currentVisibility) {
      payload['visibility'] = newVisibility;
    }

    if (payload.isEmpty) return;

    setState(() {
      actionLoading = true;
      error = null;
    });

    try {
      final updated = await videoRepository.updateVideo(
        widget.videoId,
        title: payload['title'] as String?,
        description: payload['description'] as String?,
        visibility: payload['visibility'] as String?,
      );

      if (!mounted) return;

      setState(() {
        video = updated;
        actionLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Video updated',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF171B22),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;

      setState(() {
        error =
            e.response?.data?.toString() ??
            e.message ??
            'Failed to update video';
        actionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'Failed to update video: $e';
        actionLoading = false;
      });
    }
  }

  Future<void> deleteVideo() async {
    if (actionLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171B22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          title: const Text(
            'Delete video',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to delete this video?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      actionLoading = true;
      error = null;
    });

    try {
      await videoRepository.deleteVideo(widget.videoId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Video deleted',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF171B22),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;

      setState(() {
        error =
            e.response?.data?.toString() ??
            e.message ??
            'Failed to delete video';
        actionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'Failed to delete video: $e';
        actionLoading = false;
      });
    }
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

  String formatOwner(Map<String, dynamic> currentVideo) {
    final owner = currentVideo['owner'];
    if (owner is Map) {
      final map = Map<String, dynamic>.from(owner);
      final username = map['username']?.toString().trim();
      if (username != null && username.isNotEmpty) {
        return username;
      }
    }
    return '—';
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171E29),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _surfaceBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: _secondaryTextColor,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: _secondaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _titleColor,
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _surfaceBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentVideo = video;
    final effectiveHlsUrl =
        playback?['hls_url']?.toString() ??
        currentVideo?['hls_url']?.toString();
    final effectiveHlsReady =
        playback?['hls_ready'] == true || currentVideo?['hls_ready'] == true;
    final titleText =
        currentVideo?['title']?.toString().trim().isNotEmpty == true
            ? currentVideo!['title'].toString().trim()
            : 'Video #${widget.videoId}';
    final descriptionText =
        currentVideo?['description']?.toString().trim() ?? '';
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1017),
      appBar: isLandscape
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(titleText),
              actions: [
                IconButton(
                  onPressed: actionLoading ? null : editVideo,
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit',
                ),
                IconButton(
                  onPressed: actionLoading ? null : deleteVideo,
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete',
                ),
                IconButton(
                  onPressed: (_requestInFlight || actionLoading)
                      ? null
                      : () {
                          setState(() {
                            loading = true;
                            error = null;
                          });
                          loadVideo();
                        },
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
      extendBodyBehindAppBar: !isLandscape,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : currentVideo == null
          ? const Center(child: Text('Видео не найдено'))
          : isLandscape
          ? ColoredBox(
              color: Colors.black,
              child: effectiveHlsReady && effectiveHlsUrl != null
                  ? HlsPlayer(
                      url: effectiveHlsUrl,
                      immersive: true,
                      allowSeeking: true,
                      allowQualitySelection: true,
                    )
                  : const Center(
                      child: Text(
                        'Видео ещё не готово',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF111826),
                          const Color(0xFF0B1017),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -120,
                  left: -40,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF7C91FF).withOpacity(0.10),
                    ),
                  ),
                ),
                Positioned(
                  top: 120,
                  right: -50,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.cyanAccent.withOpacity(0.06),
                    ),
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final topSpacing = constraints.maxHeight * 0.08;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: topSpacing),
                              _glassCard(
                                padding: const EdgeInsets.all(10),
                                child: effectiveHlsReady && effectiveHlsUrl != null
                                    ? HlsPlayer(
                                        url: effectiveHlsUrl,
                                        allowSeeking: true,
                                        allowQualitySelection: true,
                                      )
                                    : Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(28),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0E141D),
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        child: const Text(
                                          'Видео ещё подготавливается',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 18),
                              _glassCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titleText,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        color: _titleColor,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _metaChip(
                                          Icons.schedule_outlined,
                                          formatDuration(currentVideo['duration']),
                                        ),
                                        _metaChip(
                                          Icons.person_outline,
                                          formatOwner(currentVideo),
                                        ),
                                        _metaChip(
                                          Icons.calendar_today_outlined,
                                          formatDateTime(currentVideo['uploaded_at']),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (descriptionText.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                _glassCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _sectionTitle('Описание'),
                                      Text(
                                        descriptionText,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.6,
                                          color: _primaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}