import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repositories/live_repository.dart';
import '../widgets/hls_player.dart';

class LiveViewScreen extends StatefulWidget {
  final LiveRepository liveRepository;
  final String title;
  final String streamKey;
  final String hlsUrl;
  final String? status;

  const LiveViewScreen({
    super.key,
    required this.liveRepository,
    required this.title,
    required this.streamKey,
    required this.hlsUrl,
    this.status,
  });

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  bool loading = false;
  String? error;

  late String title;
  late String streamKey;
  late String hlsUrl;
  String? status;

  @override
  void initState() {
    super.initState();
    title = widget.title;
    streamKey = widget.streamKey;
    hlsUrl = widget.hlsUrl;
    status = widget.status;
    _enableViewerOrientations();
  }

  Future<void> _enableViewerOrientations() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _restoreDefaultOrientations() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> refreshLive() async {
    if (loading) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await widget.liveRepository.getSession(streamKey);
      final session = result['session'] is Map
          ? Map<String, dynamic>.from(result['session'] as Map)
          : <String, dynamic>{};

      final nextHlsUrl = result['hls_url']?.toString().trim() ?? '';
      final nextStatus = session['status']?.toString();
      final nextTitleRaw = session['title']?.toString().trim();

      if (!mounted) return;

      setState(() {
        hlsUrl = nextHlsUrl.isNotEmpty ? nextHlsUrl : hlsUrl;
        status = nextStatus;
        title = (nextTitleRaw != null && nextTitleRaw.isNotEmpty)
            ? nextTitleRaw
            : title;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'Не удалось обновить live: $e';
        loading = false;
      });
    }
  }

  String _displayValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '—';
    }
    return trimmed;
  }

  @override
  void dispose() {
    _restoreDefaultOrientations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title.trim().isNotEmpty ? title.trim() : 'Live';
    final description = _displayValue(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(effectiveTitle),
        actions: [
          IconButton(
            onPressed: loading ? null : refreshLive,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/live_background.png',
            fit: BoxFit.cover,
          ),
          Container(
            color: Colors.black.withOpacity(0.55),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loading) const LinearProgressIndicator(),
                if (loading) const SizedBox(height: 12),
                if (error != null) ...[
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: HlsPlayer(url: hlsUrl),
                ),
                const SizedBox(height: 20),
                Text(
                  effectiveTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (description != '—') ...[
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}