import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtmp_streaming/camera.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_config.dart';
import '../core/network/error_parser.dart';
import '../repositories/live_repository.dart';

enum LiveViewState {
  idle,
  preparingCamera,
  creatingSession,
  connectingRtmp,
  streaming,
  waitingForHls,
  live,
  stopping,
  stopped,
  failed,
}

class LiveScreen extends StatefulWidget {
  final LiveRepository liveRepository;

  const LiveScreen({
    super.key,
    required this.liveRepository,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  static const Duration _pollingBaseInterval = Duration(seconds: 3);
  static const Duration _pollingMaxInterval = Duration(seconds: 30);
  static const int _maxPollingErrorRetries = 5;

  static const Duration _streamStatsInterval = Duration(seconds: 2);
  static const Duration _hlsCheckInterval = Duration(seconds: 2);
  static const Duration _hlsCheckTimeout = Duration(seconds: 60);

  LiveRepository get liveRepository => widget.liveRepository;

  final TextEditingController _titleController = TextEditingController();

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

  LiveViewState _viewState = LiveViewState.idle;

  Timer? _pollingTimer;
  bool _pollingInProgress = false;
  bool _pollingActive = false;
  int _pollingFailureCount = 0;
  int _pollingGeneration = 0;

  Timer? _statsTimer;
  bool _statsActive = false;
  bool _statsSupported = true;
  int? _lastVideoBytesSent;
  int? _lastAudioBytesSent;
  int? _lastFramesEncoded;
  DateTime? _lastStatsAt;

  Timer? _hlsCheckTimer;
  bool _hlsCheckActive = false;
  DateTime? _liveStartedAt;
  DateTime? _hlsFirstAvailableAt;
  bool _hlsReadyLogged = false;
  int? _lastLoggedHlsStatusCode;

  int _cameraInitGeneration = 0;
  int _cameraPreviewVersion = 0;
  bool _resumeRecoveryInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lockLiveOrientation());
    _resetScreenStateForEntry();
    unawaited(_initializeEverything());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _cameraInitGeneration += 1;
    _stopPolling();
    _stopStatsMonitoring();
    _stopHlsAvailabilityCheck();
    unawaited(_disposeCameraOnly());
    unawaited(_unlockOrientation());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _lockLiveOrientation() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _unlockOrientation() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _resetScreenStateForEntry() {
    _stopPolling();
    _stopStatsMonitoring();
    _stopHlsAvailabilityCheck();

    session = null;
    rtmpUrl = null;
    hlsUrl = null;
    error = null;

    loading = false;
    isStreaming = false;
    permissionsGranted = false;
    cameraInitialized = false;
    microphoneEnabled = true;
    flashEnabled = false;

    cameras = [];
    currentCameraIndex = 0;

    _viewState = LiveViewState.idle;
    _syncWakeLock();
  }

  void _resetSessionRuntimeState() {
    _stopPolling();
    _stopStatsMonitoring();
    _stopHlsAvailabilityCheck();

    session = null;
    rtmpUrl = null;
    hlsUrl = null;
    isStreaming = false;
    loading = false;
    _syncWakeLock();
  }

  void _setViewState(
    LiveViewState newState, {
    String? errorMessage,
    bool clearError = false,
  }) {
    if (!mounted) return;

    final shouldUpdate =
        _viewState != newState || errorMessage != null || clearError;

    if (!shouldUpdate) return;

    _logLiveStep('STATE => $_viewState -> $newState');

    setState(() {
      _viewState = newState;
      if (clearError) {
        error = null;
      }
      if (errorMessage != null) {
        error = errorMessage;
      }
    });

    _syncWakeLock();
  }

  void _syncWakeLock() {
    final shouldKeepAwake = isStreaming ||
        loading ||
        _viewState == LiveViewState.waitingForHls ||
        _viewState == LiveViewState.connectingRtmp ||
        _viewState == LiveViewState.creatingSession ||
        _viewState == LiveViewState.streaming ||
        _viewState == LiveViewState.live;

    if (shouldKeepAwake) {
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(WakelockPlus.disable());
    }
  }

  Future<void> _disposeCameraOnly() async {
    final controller = cameraController;
    cameraController = null;
    cameraInitialized = false;

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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logLiveStep('APP LIFECYCLE => $state');

    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _syncWakeLock();
    }
  }

  Future<void> _handleAppResumed() async {
    if (_resumeRecoveryInProgress) return;
    _resumeRecoveryInProgress = true;

    try {
      if (!mounted) return;

      _syncWakeLock();

      if (isStreaming) {
        if (mounted && cameraController != null) {
          setState(() {
            _cameraPreviewVersion += 1;
          });
        }
        return;
      }

      await _initializeEverything();
    } finally {
      _resumeRecoveryInProgress = false;
    }
  }

  Future<void> _initializeEverything() async {
    final generation = ++_cameraInitGeneration;
    _setViewState(LiveViewState.preparingCamera, clearError: true);

    try {
      await _disposeCameraOnly();

      final granted = await _ensurePermissions();
      if (!mounted || generation != _cameraInitGeneration) return;

      if (!granted) {
        setState(() {
          permissionsGranted = false;
          cameraInitialized = false;
        });
        _setViewState(
          LiveViewState.failed,
          errorMessage:
              'Camera and microphone permissions are required for live streaming.',
        );
        return;
      }

      final available = await availableCameras();
      if (!mounted || generation != _cameraInitGeneration) return;

      if (available.isEmpty) {
        setState(() {
          permissionsGranted = true;
          cameraInitialized = false;
        });
        _setViewState(
          LiveViewState.failed,
          errorMessage: 'Camera not found',
        );
        return;
      }

      final nextCameraIndex = _preferredCameraIndex(available);

      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
        androidUseOpenGL: true,
      );

      await controller.initialize(available[nextCameraIndex]);

      if (!mounted || generation != _cameraInitGeneration) {
        await controller.dispose();
        return;
      }

      setState(() {
        permissionsGranted = true;
        cameras = available;
        currentCameraIndex = nextCameraIndex;
        cameraController = controller;
        cameraInitialized = controller.value.isInitialized == true;
        microphoneEnabled = true;
        flashEnabled = false;
        error = null;
        _viewState = LiveViewState.idle;
        _cameraPreviewVersion += 1;
      });

      _syncWakeLock();
    } catch (e) {
      if (!mounted || generation != _cameraInitGeneration) return;
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Failed to initialize live: $e',
      );
    }
  }

  int _preferredCameraIndex(List<CameraDescription> available) {
    final backIndex = available.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    return backIndex >= 0 ? backIndex : 0;
  }

  bool _isFrontCameraIndex(int index) {
    if (index < 0 || index >= cameras.length) return false;
    return cameras[index].lensDirection == CameraLensDirection.front;
  }

  Future<bool> _ensurePermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    return cameraStatus.isGranted && micStatus.isGranted;
  }

  void _applySessionResponse(Map<String, dynamic> response) {
    final previousRtmpUrl = rtmpUrl;
    final previousHlsUrl = hlsUrl;

    final rawSession = response['session'];

    final normalizedSession = rawSession is Map
        ? Map<String, dynamic>.from(rawSession as Map)
        : Map<String, dynamic>.from(response);

    session = normalizedSession;

    rtmpUrl = response['rtmp_url']?.toString() ??
        normalizedSession['rtmp_url']?.toString() ??
        previousRtmpUrl;

    hlsUrl = response['hls_url']?.toString() ??
        normalizedSession['hls_url']?.toString() ??
        previousHlsUrl;

    final status = session?['status']?.toString();
    if (status == 'stopped') {
      _viewState = LiveViewState.stopped;
      isStreaming = false;
    } else if (status == 'expired' || status == 'error') {
      _viewState = LiveViewState.failed;
      isStreaming = false;
    }

    _syncWakeLock();
  }

  void _logLiveStep(String message) {
    if (!AppConfig.enableNetworkLogs) return;
    debugPrint('[${DateTime.now().toIso8601String()}] LIVE $message');
  }

  String _mapLiveStartError(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    final mapped = NetworkErrorMapper.map(
      error,
      fallbackMessage: 'Failed to start live stream.',
    );

    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return mapped;
    }

    if (mapped == 'Failed to start live stream.') {
      return 'Failed to start live stream: $raw';
    }

    return '$mapped\n$raw';
  }

  bool _isTerminalSessionStatus(String? status) {
    return status == 'stopped' || status == 'expired' || status == 'error';
  }

  Duration _currentPollingDelay() {
    if (_pollingFailureCount <= 0) {
      return _pollingBaseInterval;
    }

    final seconds =
        _pollingBaseInterval.inSeconds * (1 << _pollingFailureCount);
    final cappedSeconds = seconds > _pollingMaxInterval.inSeconds
        ? _pollingMaxInterval.inSeconds
        : seconds;

    return Duration(seconds: cappedSeconds);
  }

  void _cancelPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _stopPolling() {
    _pollingActive = false;
    _pollingGeneration += 1;
    _pollingFailureCount = 0;
    _cancelPollingTimer();
    _logLiveStep('SESSION POLLING STOPPED');
  }

  void _scheduleNextPollingTick(int generation) {
    if (!_pollingActive || !mounted) return;
    if (generation != _pollingGeneration) return;

    _cancelPollingTimer();

    final delay = _currentPollingDelay();
    _logLiveStep(
      'SESSION POLLING SCHEDULED => delay=${delay.inSeconds}s, retry=$_pollingFailureCount, generation=$generation',
    );

    _pollingTimer = Timer(delay, () {
      unawaited(_pollSessionStatus(generation: generation));
    });
  }

  void _startPolling() {
    final streamKey = session?['stream_key']?.toString();
    final status = session?['status']?.toString();

    if (streamKey == null || streamKey.isEmpty) {
      _logLiveStep('SESSION POLLING NOT STARTED => stream_key is empty');
      return;
    }
    if (_isTerminalSessionStatus(status)) {
      _logLiveStep(
        'SESSION POLLING NOT STARTED => terminal status=${status ?? 'null'}',
      );
      return;
    }
    if (_pollingActive) {
      _logLiveStep('SESSION POLLING ALREADY ACTIVE => skip');
      return;
    }

    _pollingActive = true;
    _pollingFailureCount = 0;
    _pollingGeneration += 1;

    final generation = _pollingGeneration;
    _logLiveStep(
      'SESSION POLLING STARTED => stream_key=$streamKey, generation=$generation',
    );

    _scheduleNextPollingTick(generation);
  }

  Future<void> _pollSessionStatus({
    bool manual = false,
    int? generation,
  }) async {
    final activeGeneration = generation ?? _pollingGeneration;

    if (!manual) {
      if (!_pollingActive) return;
      if (activeGeneration != _pollingGeneration) return;
    }

    if (_pollingInProgress) {
      _logLiveStep('SESSION POLLING SKIPPED => request already in progress');
      return;
    }

    if (!mounted) return;

    final streamKey = session?['stream_key']?.toString();
    if (streamKey == null || streamKey.isEmpty) {
      _stopPolling();
      return;
    }

    final currentStatus = session?['status']?.toString();
    if (_isTerminalSessionStatus(currentStatus)) {
      _stopPolling();
      return;
    }

    _pollingInProgress = true;

    try {
      final updated = await liveRepository.getSession(streamKey);

      if (!mounted) return;

      if (!manual) {
        if (!_pollingActive) {
          _logLiveStep(
            'SESSION POLLING RESULT IGNORED => polling already stopped',
          );
          return;
        }
        if (activeGeneration != _pollingGeneration) {
          _logLiveStep(
            'SESSION POLLING RESULT IGNORED => stale generation=$activeGeneration current=$_pollingGeneration',
          );
          return;
        }
      }

      final previousStatus = session?['status']?.toString();

      setState(() {
        _applySessionResponse(updated);
      });

      final updatedStatus = session?['status']?.toString();
      if (previousStatus != updatedStatus) {
        _logLiveStep(
          'SESSION STATUS CHANGED => ${previousStatus ?? 'null'} -> ${updatedStatus ?? 'null'}',
        );
      }

      _pollingFailureCount = 0;

      if (_isTerminalSessionStatus(updatedStatus)) {
        _stopPolling();
        _stopStatsMonitoring();
        _stopHlsAvailabilityCheck();

        if (mounted) {
          setState(() {
            isStreaming = false;
            if (updatedStatus == 'stopped') {
              _viewState = LiveViewState.stopped;
            } else {
              _viewState = LiveViewState.failed;
            }
          });
          _syncWakeLock();
        }

        return;
      }
    } catch (e) {
      if (!manual) {
        if (!_pollingActive || activeGeneration != _pollingGeneration) {
          _logLiveStep(
            'SESSION POLLING ERROR IGNORED => stale/disabled generation=$activeGeneration error=$e',
          );
          return;
        }
      }

      _pollingFailureCount += 1;
      _logLiveStep(
        'SESSION POLLING ERROR => retry=$_pollingFailureCount error=$e',
      );

      if (_pollingFailureCount >= _maxPollingErrorRetries) {
        _stopPolling();

        if (!mounted) return;

        _setViewState(
          LiveViewState.failed,
          errorMessage: error ?? 'Failed to refresh live session status.',
        );
        return;
      }
    } finally {
      _pollingInProgress = false;
    }

    if (!manual) {
      _scheduleNextPollingTick(activeGeneration);
    }
  }

  Future<void> _refreshSessionStatus() async {
    if (_pollingInProgress || loading) return;
    await _pollSessionStatus(manual: true);
  }

  Future<Map<String, dynamic>?> _tryReadStreamingStats(
    CameraController controller,
  ) async {
    try {
      final dynamic result = await controller.getStreamStatistics();
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      if (_statsSupported) {
        _statsSupported = false;
        _logLiveStep('STATS NOT AVAILABLE => $e');
      }
    }
    return null;
  }

  int? _readIntStat(Map<String, dynamic> stats, List<String> keys) {
    for (final key in keys) {
      final value = stats[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  double _safeSecondsBetween(DateTime a, DateTime b) {
    final ms = a.difference(b).inMilliseconds.abs();
    return math.max(ms / 1000.0, 0.001);
  }

  void _startStatsMonitoring() {
    if (_statsActive) return;
    if (cameraController == null) return;

    _statsActive = true;
    _statsSupported = true;
    _lastVideoBytesSent = null;
    _lastAudioBytesSent = null;
    _lastFramesEncoded = null;
    _lastStatsAt = null;

    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_streamStatsInterval, (_) {
      unawaited(_collectStreamingStats());
    });
  }

  void _stopStatsMonitoring() {
    _statsActive = false;
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastVideoBytesSent = null;
    _lastAudioBytesSent = null;
    _lastFramesEncoded = null;
    _lastStatsAt = null;
  }

  Future<void> _collectStreamingStats() async {
    if (!_statsActive || !isStreaming) return;

    final controller = cameraController;
    if (controller == null) return;

    final stats = await _tryReadStreamingStats(controller);
    if (stats == null || stats.isEmpty) return;

    final now = DateTime.now();
    final videoBytes = _readIntStat(stats, [
      'videoBytesSent',
      'video_bytes_sent',
      'sentVideoBytes',
      'bytesSentVideo',
    ]);
    final audioBytes = _readIntStat(stats, [
      'audioBytesSent',
      'audio_bytes_sent',
      'sentAudioBytes',
      'bytesSentAudio',
    ]);
    final totalBytes = _readIntStat(stats, [
      'totalBytesSent',
      'total_bytes_sent',
      'bytesSent',
    ]);
    final framesEncoded = _readIntStat(stats, [
      'videoFramesEncoded',
      'video_frames_encoded',
      'framesEncoded',
      'frames_encoded',
      'sentVideoFrames',
    ]);

    if (_lastStatsAt != null) {
      final seconds = _safeSecondsBetween(now, _lastStatsAt!);

      int? bytesDelta;
      if (videoBytes != null || audioBytes != null) {
        final prevVideo = _lastVideoBytesSent ?? 0;
        final prevAudio = _lastAudioBytesSent ?? 0;
        final curVideo = videoBytes ?? 0;
        final curAudio = audioBytes ?? 0;
        bytesDelta = (curVideo - prevVideo) + (curAudio - prevAudio);
      } else if (totalBytes != null) {
        final prevTotal =
            (_lastVideoBytesSent ?? 0) + (_lastAudioBytesSent ?? 0);
        bytesDelta = totalBytes - prevTotal;
      }

      double? bitrateKbps;
      if (bytesDelta != null && bytesDelta >= 0) {
        bitrateKbps = (bytesDelta * 8) / seconds / 1000.0;
      }

      double? fps;
      if (framesEncoded != null && _lastFramesEncoded != null) {
        final framesDelta = framesEncoded - _lastFramesEncoded!;
        if (framesDelta >= 0) {
          fps = framesDelta / seconds;
        }
      }

      final parts = <String>[];

      if (bitrateKbps != null) {
        parts.add('bitrate=${bitrateKbps.toStringAsFixed(1)} kbps');
      }
      if (fps != null) {
        parts.add('fps=${fps.toStringAsFixed(1)}');
      }
      if (videoBytes != null) {
        parts.add('videoBytes=$videoBytes');
      }
      if (audioBytes != null) {
        parts.add('audioBytes=$audioBytes');
      }
      if (framesEncoded != null) {
        parts.add('frames=$framesEncoded');
      }

      if (parts.isNotEmpty) {
        _logLiveStep('STATS ${parts.join(', ')}');
      }
    }

    _lastStatsAt = now;
    _lastVideoBytesSent = videoBytes ?? _lastVideoBytesSent ?? totalBytes ?? 0;
    _lastAudioBytesSent = audioBytes ?? _lastAudioBytesSent ?? 0;
    _lastFramesEncoded = framesEncoded ?? _lastFramesEncoded;
  }

  void _startHlsAvailabilityCheck() {
    if (_hlsCheckActive) return;
    if (hlsUrl == null || hlsUrl!.isEmpty) return;

    _liveStartedAt = DateTime.now();
    _hlsFirstAvailableAt = null;
    _hlsReadyLogged = false;
    _lastLoggedHlsStatusCode = null;
    _hlsCheckActive = true;

    _hlsCheckTimer?.cancel();
    _hlsCheckTimer = Timer.periodic(_hlsCheckInterval, (_) {
      unawaited(_checkHlsAvailability());
    });
  }

  void _stopHlsAvailabilityCheck() {
    _hlsCheckActive = false;
    _hlsCheckTimer?.cancel();
    _hlsCheckTimer = null;
    _lastLoggedHlsStatusCode = null;
    _liveStartedAt = null;
    _hlsFirstAvailableAt = null;
    _hlsReadyLogged = false;
  }

  Future<void> _checkHlsAvailability() async {
    if (!_hlsCheckActive) return;

    final liveUrl = hlsUrl;
    if (liveUrl == null || liveUrl.isEmpty) {
      _logLiveStep('HLS CHECK STOPPED => hlsUrl is empty');
      _stopHlsAvailabilityCheck();
      return;
    }

    final startedAt = _liveStartedAt;
    if (startedAt == null) {
      _stopHlsAvailabilityCheck();
      return;
    }

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed > _hlsCheckTimeout) {
      _logLiveStep(
        'HLS CHECK TIMEOUT => no playlist after ${elapsed.inSeconds}s',
      );
      _stopHlsAvailabilityCheck();
      return;
    }

    final result = await liveRepository.checkHlsAvailability(liveUrl);

    if (_lastLoggedHlsStatusCode != result.statusCode || !result.available) {
      _logLiveStep(
        'HLS CHECK => status=${result.statusCode ?? 'network_error'}, available=${result.available}',
      );
      _lastLoggedHlsStatusCode = result.statusCode;
    }

    if (result.available && !_hlsReadyLogged) {
      _hlsFirstAvailableAt = DateTime.now();
      final latency = _hlsFirstAvailableAt!.difference(startedAt);
      _hlsReadyLogged = true;

      if (mounted) {
        setState(() {
          _viewState = LiveViewState.live;
        });
        _syncWakeLock();
      }

      _logLiveStep(
        'HLS READY => latency=${latency.inMilliseconds} ms, url=$liveUrl',
      );
      _stopHlsAvailabilityCheck();
    }
  }

  Future<void> startLive() async {
    if (loading || isStreaming) return;

    final controller = cameraController;
    if (controller == null || !cameraInitialized) {
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Camera is not initialized yet',
      );
      return;
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Enter stream title',
      );
      return;
    }

    _resetSessionRuntimeState();

    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        session = null;
        rtmpUrl = null;
        hlsUrl = null;
        _viewState = LiveViewState.creatingSession;
      });
      _syncWakeLock();
    }

    int? createdSessionId;

    try {
      _logLiveStep('START REQUESTED');

      final res = await liveRepository.createSession(title: title);
      _logLiveStep('SESSION CREATED');

      if (!mounted) return;

      setState(() {
        _applySessionResponse(res);
      });

      final rawId = session?['id'];
      createdSessionId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      final targetRtmpUrl = rtmpUrl;
      if (targetRtmpUrl == null || targetRtmpUrl.isEmpty) {
        throw const ApiException(
          NetworkErrorMapper.invalidResponseMessage,
        );
      }

      _logLiveStep('RTMP URL => $targetRtmpUrl');

      if (mounted) {
        setState(() {
          _viewState = LiveViewState.connectingRtmp;
        });
        _syncWakeLock();
      }

      _logLiveStep('START VIDEO STREAMING START');
      await controller.startVideoStreaming(
        targetRtmpUrl,
        bitrate: 1200 * 1024,
      );
      _logLiveStep('START VIDEO STREAMING OK');

      if (!mounted) return;

      setState(() {
        isStreaming = true;
        loading = false;
        error = null;
        _viewState = LiveViewState.waitingForHls;
      });

      _syncWakeLock();
      _startPolling();
      _startStatsMonitoring();
      _startHlsAvailabilityCheck();
    } catch (e) {
      _logLiveStep('START LIVE ERROR => $e');

      if (createdSessionId != null) {
        try {
          _logLiveStep('START LIVE CLEANUP => stop session id=$createdSessionId');
          await liveRepository.stopSession(createdSessionId);
        } catch (cleanupError) {
          _logLiveStep('START LIVE CLEANUP ERROR => $cleanupError');
        }
      }

      if (!mounted) return;

      setState(() {
        error = _mapLiveStartError(e);
        loading = false;
        isStreaming = false;
        session = null;
        rtmpUrl = null;
        hlsUrl = null;
        _viewState = LiveViewState.failed;
      });

      _syncWakeLock();
    }
  }

  Future<void> stopLive() async {
    final rawId = session?['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    if (id == null) {
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Invalid session id',
      );
      return;
    }

    _stopPolling();
    _stopStatsMonitoring();
    _stopHlsAvailabilityCheck();

    setState(() {
      loading = true;
      error = null;
      _viewState = LiveViewState.stopping;
    });
    _syncWakeLock();

    try {
      final controller = cameraController;
      if (controller != null && controller.value.isStreamingVideoRtmp == true) {
        _logLiveStep('STOP VIDEO STREAMING START');
        await controller.stopVideoStreaming();
        _logLiveStep('STOP VIDEO STREAMING OK');
      }

      _logLiveStep('STOP SESSION REQUEST => id=$id');
      await liveRepository.stopSession(id);
      _logLiveStep('STOP SESSION OK => id=$id');

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
            'stopped_at': DateTime.now().toUtc().toIso8601String(),
          };
        }

        hlsUrl = null;
        rtmpUrl = null;
        _viewState = LiveViewState.stopped;
      });

      _syncWakeLock();
    } catch (e) {
      _logLiveStep('STOP LIVE ERROR => $e');

      if (!mounted) return;
      setState(() {
        error = NetworkErrorMapper.map(
          e,
          fallbackMessage: 'Failed to stop live stream.',
        );
        loading = false;
        _viewState = LiveViewState.failed;
      });

      _syncWakeLock();
    }
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) return;

    final controller = cameraController;
    if (controller == null || !cameraInitialized) return;
    if (loading) return;

    try {
      final nextIndex = (currentCameraIndex + 1) % cameras.length;

      await controller.switchCamera(cameras[nextIndex].name!);

      if (!mounted) return;

      setState(() {
        currentCameraIndex = nextIndex;
        if (_isFrontCameraIndex(currentCameraIndex)) {
          flashEnabled = false;
        }
        _cameraPreviewVersion += 1;
      });
    } catch (e) {
      if (!mounted) return;
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Failed to switch camera: $e',
      );
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
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Failed to toggle microphone: $e',
      );
    }
  }

  Future<void> toggleFlash() async {
    final controller = cameraController;
    if (controller == null) return;

    if (_isFrontCameraIndex(currentCameraIndex)) {
      if (!mounted) return;
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Flash is not available for the front camera.',
      );
      return;
    }

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
      _setViewState(
        LiveViewState.failed,
        errorMessage: 'Failed to toggle flash: $e',
      );
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

  String _stateTitle() {
    switch (_viewState) {
      case LiveViewState.idle:
        return 'Ready to start';
      case LiveViewState.preparingCamera:
        return 'Preparing camera';
      case LiveViewState.creatingSession:
        return 'Creating live session';
      case LiveViewState.connectingRtmp:
        return 'Connecting to RTMP';
      case LiveViewState.streaming:
        return 'Stream started';
      case LiveViewState.waitingForHls:
        return 'Waiting for HLS';
      case LiveViewState.live:
        return 'Live is on';
      case LiveViewState.stopping:
        return 'Stopping stream';
      case LiveViewState.stopped:
        return 'Stream stopped';
      case LiveViewState.failed:
        return 'Live error';
    }
  }

  Color _stateColor() {
    switch (_viewState) {
      case LiveViewState.live:
        return Colors.red;
      case LiveViewState.waitingForHls:
      case LiveViewState.streaming:
      case LiveViewState.connectingRtmp:
      case LiveViewState.creatingSession:
      case LiveViewState.preparingCamera:
      case LiveViewState.stopping:
      case LiveViewState.idle:
        return Colors.blue;
      case LiveViewState.stopped:
        return Colors.grey;
      case LiveViewState.failed:
        return Colors.red;
    }
  }

  bool get _canStartLive {
    return !loading && !isStreaming && cameraInitialized;
  }

  bool get _canStopLive {
    final status = session?['status']?.toString();
    final hasSession = session != null;

    if (loading || !hasSession) return false;
    if (_isTerminalSessionStatus(status)) return false;

    return true;
  }

  String _streamDisplayTitle() {
    final title = session?['title']?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    final inputTitle = _titleController.text.trim();
    if (inputTitle.isNotEmpty) {
      return inputTitle;
    }

    return 'Untitled stream';
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = session != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live producer'),
        actions: [
          IconButton(
            onPressed: cameras.length > 1 && cameraInitialized && !loading
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
            onPressed: permissionsGranted && !_isFrontCameraIndex(currentCameraIndex)
                ? toggleFlash
                : null,
            icon: Icon(flashEnabled ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Toggle flash',
          ),
          IconButton(
            onPressed: (session?['stream_key'] != null && !loading)
                ? _refreshSessionStatus
                : null,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh status',
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
                if (!permissionsGranted)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Text(
                      'Camera and microphone permissions are required for live streaming.',
                    ),
                  ),
                if (!permissionsGranted) const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  enabled: !isStreaming && !loading,
                  decoration: InputDecoration(
                    labelText: 'Stream title',
                    hintText: 'Enter stream title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                      child: KeyedSubtree(
                        key: ValueKey(_cameraPreviewVersion),
                        child: CameraPreview(cameraController!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _canStartLive ? startLive : null,
                        child: const Text('Start live'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _canStopLive ? stopLive : null,
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
                if (hasSession || _viewState != LiveViewState.idle) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _streamDisplayTitle(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _stateTitle(),
                          style: TextStyle(
                            color: _stateColor(),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (session?['started_at'] != null) ...[
                          const SizedBox(height: 8),
                          Text('Started: ${_formatDate(session?['started_at'])}'),
                        ],
                        if (session?['stopped_at'] != null) ...[
                          const SizedBox(height: 8),
                          Text('Stopped: ${_formatDate(session?['stopped_at'])}'),
                        ],
                      ],
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