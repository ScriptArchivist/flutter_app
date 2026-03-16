import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtmp_streaming/camera.dart';

import '../repositories/live_repository.dart';
import '../widgets/hls_player.dart';

class LiveScreen extends StatefulWidget {
  final LiveRepository liveRepository;

  const LiveScreen({
    super.key,
    required this.liveRepository,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  LiveRepository get liveRepository => widget.liveRepository;

  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  int currentCameraIndex = 0;

  bool loading = false;
  bool isStreaming = false;
  bool permissionsGranted = false;
  bool cameraInitialized = false;
  bool microphoneEnabled = true;
  bool flashEnabled = false;

  String? error;
  Map<String, dynamic>? session;
  String? rtmpUrl;
  String? hlsUrl;

  Timer? pollingTimer;
  bool _pollingInProgress = false;

  @override
  void initState() {
    super.initState();
    _initializeEverything();
  }

  Future<void> _initializeEverything() async {
    try {
      final granted = await _ensurePermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          permissionsGranted = false;
          error = 'Нужны разрешения на камеру и микрофон';
        });
        return;
      }

      final available = await availableCameras();

      if (!mounted) return;

      if (available.isEmpty) {
        setState(() {
          permissionsGranted = true;
          error = 'Камера не найдена';
        });
        return;
      }

      cameras = available;
      currentCameraIndex = _preferredCameraIndex(available);

      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
        androidUseOpenGL: true,
      );

      await controller.initialize(available[currentCameraIndex]);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        permissionsGranted = true;
        cameraController = controller;
        cameraInitialized = controller.value.isInitialized == true;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось инициализировать live: $e';
      });
    }
  }

  int _preferredCameraIndex(List<CameraDescription> available) {
    final backIndex = available.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    return backIndex >= 0 ? backIndex : 0;
  }

  Future<bool> _ensurePermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    return cameraStatus.isGranted && micStatus.isGranted;
  }

  void _applySessionResponse(Map<String, dynamic> response) {
    final rawSession = response['session'];

    final normalizedSession = rawSession is Map
        ? Map<String, dynamic>.from(rawSession as Map)
        : Map<String, dynamic>.from(response);

    session = normalizedSession;
    rtmpUrl =
        response['rtmp_url']?.toString() ??
        normalizedSession['rtmp_url']?.toString();
    hlsUrl =
        response['hls_url']?.toString() ??
        normalizedSession['hls_url']?.toString();
  }

  Future<void> startLive() async {
    if (loading || isStreaming) return;

    final controller = cameraController;
    if (controller == null || !cameraInitialized) {
      setState(() {
        error = 'Камера ещё не инициализирована';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await liveRepository.createSession();

      if (!mounted) return;

      _applySessionResponse(res);

      final targetRtmpUrl = rtmpUrl;
      if (targetRtmpUrl == null || targetRtmpUrl.isEmpty) {
        throw Exception('Backend did not return RTMP URL');
      }

      await controller.prepareForVideoStreaming();
      await controller.startVideoStreaming(
        targetRtmpUrl,
        bitrate: 1200 * 1024,
      );

      if (!mounted) return;

      setState(() {
        isStreaming = true;
        loading = false;
        error = null;
      });

      startPolling();
    } on DioException catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.response?.data?.toString() ?? e.message ?? 'Live start failed';
        loading = false;
        isStreaming = false;
      });
    } catch (e) {
      final rawId = session?['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      if (id != null) {
        try {
          await liveRepository.stopSession(id);
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        error = 'Live start failed: $e';
        loading = false;
        isStreaming = false;
        session = null;
        rtmpUrl = null;
        hlsUrl = null;
      });
    }
  }

  void startPolling() {
    pollingTimer?.cancel();

    final streamKey = session?['stream_key']?.toString();
    if (streamKey == null || streamKey.isEmpty) return;

    pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_pollingInProgress) return;
      _pollingInProgress = true;

      try {
        final updated = await liveRepository.getSession(streamKey);

        if (!mounted) return;

        setState(() {
          _applySessionResponse(updated);
        });

        final status = session?['status']?.toString();
        if (status == 'stopped' || status == 'expired' || status == 'error') {
          pollingTimer?.cancel();
        }
      } catch (_) {
      } finally {
        _pollingInProgress = false;
      }
    });
  }

  Future<void> stopLive() async {
    final rawId = session?['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    if (id == null) {
      setState(() {
        error = 'Invalid session id';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final controller = cameraController;
      if (controller != null && controller.value.isStreamingVideoRtmp == true) {
        await controller.stopVideoStreaming();
      }

      await liveRepository.stopSession(id);
      pollingTimer?.cancel();

      if (!mounted) return;

      setState(() {
        isStreaming = false;
        loading = false;
        microphoneEnabled = true;
        flashEnabled = false;
        if (session != null) {
          session = {
            ...session!,
            'status': 'stopped',
          };
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.response?.data?.toString() ?? e.message ?? 'Stop live failed';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Stop live failed: $e';
        loading = false;
      });
    }
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) return;

    final controller = cameraController;
    if (controller == null || !cameraInitialized) return;

    try {
      final nextIndex = (currentCameraIndex + 1) % cameras.length;
      await controller.switchCamera(cameras[nextIndex].name!);

      if (!mounted) return;

      setState(() {
        currentCameraIndex = nextIndex;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось переключить камеру: $e';
      });
    }
  }

  Future<void> toggleMicrophone() async {
    final controller = cameraController;
    if (controller == null) return;

    try {
      final newValue = !microphoneEnabled;

      if (controller.value.isStreamingVideoRtmp == true) {
        await controller.switchAudio(newValue);
      }

      if (!mounted) return;

      setState(() {
        microphoneEnabled = newValue;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось переключить микрофон: $e';
      });
    }
  }

  Future<void> toggleFlash() async {
    final controller = cameraController;
    if (controller == null) return;

    try {
      final newValue = !flashEnabled;

      if (controller.value.isStreamingVideoRtmp == true) {
        await controller.switchFlashLight(newValue);
      }

      if (!mounted) return;

      setState(() {
        flashEnabled = newValue;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось переключить вспышку: $e';
      });
    }
  }

  Future<void> _shutdownLiveResources({bool stopSessionOnBackend = false}) async {
    pollingTimer?.cancel();
    pollingTimer = null;

    final controller = cameraController;

    if (controller != null) {
      try {
        if (controller.value.isStreamingVideoRtmp == true) {
          await controller.stopVideoStreaming();
        }
      } catch (_) {}

      try {
        await controller.dispose();
      } catch (_) {}
    }

    cameraController = null;
    cameraInitialized = false;
    isStreaming = false;

    if (stopSessionOnBackend) {
      final rawId = session?['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      if (id != null) {
        try {
          await liveRepository.stopSession(id);
        } catch (_) {}
      }
    }
  }

  String _formatDate(dynamic value) {
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }

  @override
  void dispose() {
    unawaited(_shutdownLiveResources(stopSessionOnBackend: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = session?['status']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          IconButton(
            onPressed: cameras.length > 1 && cameraInitialized && !isStreaming
                ? switchCamera
                : null,
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch camera',
          ),
          IconButton(
            onPressed: permissionsGranted ? toggleMicrophone : null,
            icon: Icon(microphoneEnabled ? Icons.mic : Icons.mic_off),
            tooltip: 'Toggle microphone',
          ),
          IconButton(
            onPressed: permissionsGranted ? toggleFlash : null,
            icon: Icon(flashEnabled ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Toggle flash',
          ),
          IconButton(
            onPressed:
                (session?['stream_key'] != null && !loading) ? startPolling : null,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!permissionsGranted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'Для live нужны разрешения на камеру и микрофон.',
                ),
              ),
            if (cameraInitialized && cameraController != null) ...[
              const Text(
                'Camera preview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: cameraController!.value.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CameraPreview(cameraController!),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        (loading || isStreaming || !cameraInitialized)
                            ? null
                            : startLive,
                    child: const Text('Start live'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        (loading || session == null || !isStreaming)
                            ? null
                            : stopLive,
                    child: const Text('Stop live'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (session != null) ...[
              Text(
                isStreaming ? 'Эфир идёт' : 'Live session создана',
                style: TextStyle(
                  color: isStreaming ? Colors.red : Colors.blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              _infoRow('Статус', session?['status']?.toString() ?? '—'),
              _infoRow('Начало', _formatDate(session?['started_at'])),
              _infoRow('Истекает', _formatDate(session?['expires_at'])),
            ],
            const SizedBox(height: 16),
            if (hlsUrl != null &&
                hlsUrl!.isNotEmpty &&
                status != 'stopped' &&
                status != 'expired') ...[
              const Text(
                'Live playback',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              HlsPlayer(url: hlsUrl!),
            ],
          ],
        ),
      ),
    );
  }
}