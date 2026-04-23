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

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131A24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
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
    _restoreDefaultOrientations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title.trim().isNotEmpty ? title.trim() : 'Live';
    final description = _displayValue(status);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1017),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(effectiveTitle),
        actions: [
          IconButton(
            onPressed: loading ? null : refreshLive,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/live_background.png',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.38),
                  const Color(0xFF0B1017).withOpacity(0.88),
                ],
              ),
            ),
          ),
          Positioned(
            top: -100,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            top: 110,
            right: -60,
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
                final topSpacing = constraints.maxHeight * 0.10;

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
                        if (loading) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const LinearProgressIndicator(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (error != null) ...[
                          _glassCard(
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _glassCard(
                          padding: const EdgeInsets.all(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: HlsPlayer(url: hlsUrl),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _glassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.redAccent.withOpacity(0.45),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                effectiveTitle,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFEAF1FF),
                                  height: 1.15,
                                ),
                              ),
                              if (description != '—') ...[
                                const SizedBox(height: 14),
                                Text(
                                  description,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.6,
                                    color: Color(0xFFD8E0F0),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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