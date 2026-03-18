import 'package:flutter/material.dart';

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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title.trim().isNotEmpty ? title.trim() : 'Live';

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
      body: SingleChildScrollView(
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
            HlsPlayer(url: hlsUrl),
            const SizedBox(height: 16),
            _infoRow('Title', effectiveTitle),
            _infoRow('Status', _displayValue(status)),
            _infoRow('HLS', _displayValue(hlsUrl)),
          ],
        ),
      ),
    );
  }
}