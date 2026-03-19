import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

enum HlsPlayerState {
  initializing,
  streamNotReady,
  playing,
  error,
}

class HlsPlayer extends StatefulWidget {
  final String url;
  final bool autoplay;
  final bool immersive;
  final bool allowSeeking;
  final bool allowQualitySelection;

  const HlsPlayer({
    super.key,
    required this.url,
    this.autoplay = true,
    this.immersive = false,
    this.allowSeeking = false,
    this.allowQualitySelection = false,
  });

  @override
  State<HlsPlayer> createState() => _HlsPlayerState();
}

class _HlsPlayerState extends State<HlsPlayer> {
  static const int _maxInitAttempts = 5;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _initializeTimeout = Duration(seconds: 20);
  static const Duration _positionUpdateInterval = Duration(milliseconds: 300);
  static const Duration _controlsAutoHideDelay = Duration(seconds: 3);

  VideoPlayerController? _controller;

  HlsPlayerState _state = HlsPlayerState.initializing;
  String? _error;
  bool _unsupportedPlatform = false;

  int _initAttempt = 0;
  int _initGeneration = 0;
  Timer? _retryTimer;
  Timer? _positionTimer;
  Timer? _controlsHideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isBuffering = false;
  bool _isQualityLoading = false;

  List<_HlsQualityOption> _qualityOptions = const [];
  String? _selectedQualityUrl;

  bool _controlsVisible = true;
  bool _isDraggingSlider = false;
  double? _dragValueMs;

  @override
  void initState() {
    super.initState();
    _selectedQualityUrl = widget.url;
    _applyImmersiveMode();
    _startInitialization();
    _loadQualityOptions();
    _restartControlsAutoHide();
  }

  @override
  void didUpdateWidget(covariant HlsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      _selectedQualityUrl = widget.url;
      _qualityOptions = const [];
      _reinitialize();
      _loadQualityOptions();
    }

    if (oldWidget.immersive != widget.immersive) {
      _applyImmersiveMode();
    }
  }

  bool get _shouldUseFallback {
    if (kIsWeb) return true;

    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  bool get _canSeek {
    if (!widget.allowSeeking) return false;
    return _duration > Duration.zero;
  }

  Future<void> _applyImmersiveMode() async {
    if (kIsWeb) return;

    if (widget.immersive) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [],
      );

      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ));
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ));
    }
  }

  void _setPlayerState(HlsPlayerState newState, {String? errorMessage}) {
    if (!mounted) return;

    setState(() {
      _state = newState;
      _error = errorMessage;
    });
  }

  Future<void> _reinitialize() async {
    _retryTimer?.cancel();
    _initGeneration += 1;
    _initAttempt = 0;

    final oldController = _controller;
    _controller = null;
    _stopPositionTimer();
    _position = Duration.zero;
    _duration = Duration.zero;
    _isBuffering = false;

    if (mounted) {
      setState(() {
        _error = null;
        _unsupportedPlatform = false;
        _state = HlsPlayerState.initializing;
      });
    }

    if (oldController != null) {
      oldController.removeListener(_onControllerChanged);
      await oldController.dispose();
    }

    _startInitialization();
  }

  void _startInitialization() {
    final generation = ++_initGeneration;
    _initAttempt = 0;
    _retryTimer?.cancel();
    unawaited(_initWithRetry(generation));
  }

  Future<_InitAttemptResult> _initWithRetry(int generation) async {
    if (_shouldUseFallback) {
      if (!mounted || generation != _initGeneration) {
        return _InitAttemptResult.cancelled;
      }

      setState(() {
        _unsupportedPlatform = true;
        _state = HlsPlayerState.error;
        _error = null;
      });

      return _InitAttemptResult.error;
    }

    while (mounted &&
        generation == _initGeneration &&
        _initAttempt < _maxInitAttempts) {
      _initAttempt += 1;

      _setPlayerState(HlsPlayerState.initializing);

      final result = await _tryInitializeOnce(generation);
      if (!mounted || generation != _initGeneration) {
        return _InitAttemptResult.cancelled;
      }

      if (result == _InitAttemptResult.success) {
        return result;
      }

      if (result == _InitAttemptResult.streamNotReady) {
        if (_initAttempt >= _maxInitAttempts) {
          _setPlayerState(
            HlsPlayerState.streamNotReady,
            errorMessage: 'Live stream ещё подготавливается.',
          );
          return result;
        }

        _setPlayerState(
          HlsPlayerState.streamNotReady,
          errorMessage:
              'Live stream ещё не готов. Повторная попытка ${_initAttempt + 1}/$_maxInitAttempts...',
        );

        final completer = Completer<void>();
        _retryTimer?.cancel();
        _retryTimer = Timer(_retryDelay, () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
        await completer.future;
        continue;
      }

      if (_initAttempt >= _maxInitAttempts) {
        _setPlayerState(
          HlsPlayerState.error,
          errorMessage: _error ?? 'Не удалось инициализировать HLS player.',
        );
        return result;
      }

      final completer = Completer<void>();
      _retryTimer?.cancel();
      _retryTimer = Timer(_retryDelay, () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      await completer.future;
    }

    return _InitAttemptResult.cancelled;
  }

  Future<_InitAttemptResult> _tryInitializeOnce(int generation) async {
    VideoPlayerController? controller;

    try {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(_selectedQualityUrl ?? widget.url),
      );

      await controller.initialize().timeout(_initializeTimeout);

      if (!mounted || generation != _initGeneration) {
        await controller.dispose();
        return _InitAttemptResult.cancelled;
      }

      await controller.setLooping(false);
      controller.addListener(_onControllerChanged);

      if (widget.autoplay) {
        await controller.play();
      }

      final previousController = _controller;
      _controller = controller;

      if (previousController != null && previousController != controller) {
        previousController.removeListener(_onControllerChanged);
        await previousController.dispose();
      }

      _syncPositionFromController();
      _startPositionTimer();
      _setPlayerState(HlsPlayerState.playing);
      return _InitAttemptResult.success;
    } catch (e) {
      final message = e.toString();
      final notReady = _looksLikeStreamNotReady(message);

      if (controller != null) {
        try {
          controller.removeListener(_onControllerChanged);
        } catch (_) {}
        try {
          await controller.dispose();
        } catch (_) {}
      }

      if (!mounted || generation != _initGeneration) {
        return _InitAttemptResult.cancelled;
      }

      if (notReady) {
        _error = 'HLS playlist пока недоступен';
        return _InitAttemptResult.streamNotReady;
      }

      _error = 'Player init failed: $message';
      return _InitAttemptResult.error;
    }
  }

  bool _looksLikeStreamNotReady(String message) {
    final lower = message.toLowerCase();

    return lower.contains('404') ||
        lower.contains('403') ||
        lower.contains('source error') ||
        lower.contains('playlist') ||
        lower.contains('manifest') ||
        lower.contains('not found') ||
        lower.contains('connection closed before full header was received') ||
        lower.contains('failed to load') ||
        lower.contains('unrecognized input format') ||
        lower.contains('behind live window');
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final controller = _controller;
    if (controller == null) return;

    final value = controller.value;

    if (value.hasError) {
      final description = value.errorDescription ?? 'Playback error';

      if (_looksLikeStreamNotReady(description)) {
        _setPlayerState(
          HlsPlayerState.streamNotReady,
          errorMessage: 'Live stream ещё подготавливается.',
        );
      } else {
        _setPlayerState(
          HlsPlayerState.error,
          errorMessage: description,
        );
      }
      return;
    }

    if (!_isDraggingSlider) {
      _syncPositionFromController();
    }

    if (value.isInitialized) {
      if (_state != HlsPlayerState.playing) {
        _setPlayerState(HlsPlayerState.playing);
      } else {
        setState(() {});
      }
    }
  }

  void _syncPositionFromController() {
    final controller = _controller;
    if (controller == null) return;

    final value = controller.value;

    if (!mounted) return;

    setState(() {
      _position = value.position;
      _duration = value.duration;
      _isBuffering = value.isBuffering;
    });
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(_positionUpdateInterval, (_) {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null) return;
      if (_isDraggingSlider) return;
      _syncPositionFromController();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _restartControlsAutoHide() {
    _controlsHideTimer?.cancel();

    if (!widget.immersive) {
      return;
    }

    _controlsHideTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted) return;
      if (_isDraggingSlider) return;

      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _showControls() {
    if (!mounted) return;

    setState(() {
      _controlsVisible = true;
    });

    _restartControlsAutoHide();
  }

  void _toggleControlsVisibility() {
    if (!widget.immersive) return;

    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_controlsVisible) {
      _restartControlsAutoHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  Widget _buildVideo(VideoPlayerController controller) {
    if (widget.immersive) {
      final size = controller.value.size;
      final width = size.width <= 0 ? 16.0 : size.width;
      final height = size.height <= 0 ? 9.0 : size.height;

      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: width,
              height: height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio:
          controller.value.aspectRatio == 0
              ? (16 / 9)
              : controller.value.aspectRatio,
      child: ColoredBox(
        color: Colors.black,
        child: VideoPlayer(controller),
      ),
    );
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null) return;

    _showControls();

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _controller;
    if (controller == null || !_canSeek) return;

    final duration = _duration;
    var target = position;

    if (target < Duration.zero) {
      target = Duration.zero;
    }

    if (duration > Duration.zero && target > duration) {
      target = duration;
    }

    await controller.seekTo(target);

    if (mounted) {
      setState(() {
        _position = target;
      });
    }
  }

  Future<void> _seekRelative(Duration delta) async {
    _showControls();
    await _seekTo(_position + delta);
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusCard({
    required String title,
    required String message,
    bool showRetry = true,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(message),
            if (!widget.immersive) ...[
              const SizedBox(height: 12),
              SelectableText(widget.url),
            ],
            if (showRetry) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reinitialize,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadQualityOptions() async {
    if (!widget.allowQualitySelection) return;
    if (_shouldUseFallback) return;

    try {
      final variants = await _fetchQualityOptions(widget.url);

      if (!mounted) return;

      if (variants.isEmpty) {
        setState(() {
          _qualityOptions = const [];
        });
        return;
      }

      final autoOption = _HlsQualityOption(
        label: 'Auto',
        url: widget.url,
      );

      setState(() {
        _qualityOptions = [autoOption, ...variants];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _qualityOptions = const [];
      });
    }
  }

  Future<List<_HlsQualityOption>> _fetchQualityOptions(String masterUrl) async {
    final uri = Uri.parse(masterUrl);
    final httpClient = HttpClient();

    try {
      final request = await httpClient.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.apple.mpegurl, application/x-mpegURL, text/plain',
      );

      final response = await request.close();
      if (response.statusCode != 200) {
        return const [];
      }

      final body = await response.transform(SystemEncoding().decoder).join();
      if (!body.contains('#EXT-X-STREAM-INF')) {
        return const [];
      }

      final lines = body
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final result = <_HlsQualityOption>[];

      for (var i = 0; i < lines.length - 1; i++) {
        final line = lines[i];
        if (!line.startsWith('#EXT-X-STREAM-INF:')) {
          continue;
        }

        final nextLine = lines[i + 1];
        if (nextLine.startsWith('#')) {
          continue;
        }

        final resolutionMatch =
            RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
        final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);

        String label;
        if (resolutionMatch != null) {
          label = '${resolutionMatch.group(2)}p';
        } else if (bandwidthMatch != null) {
          final bandwidth = int.tryParse(bandwidthMatch.group(1)!);
          if (bandwidth != null) {
            label = '${(bandwidth / 1000).round()} kbps';
          } else {
            label = 'Variant';
          }
        } else {
          label = 'Variant';
        }

        final variantUrl = uri.resolve(nextLine).toString();

        if (result.any((item) => item.url == variantUrl)) {
          continue;
        }

        result.add(_HlsQualityOption(
          label: label,
          url: variantUrl,
        ));
      }

      result.sort((a, b) {
        final aValue = a.sortValue;
        final bValue = b.sortValue;
        return bValue.compareTo(aValue);
      });

      return result;
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<void> _showQualitySelector() async {
    if (_qualityOptions.isEmpty || _isQualityLoading) return;

    _showControls();

    final selectedUrl = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _qualityOptions.map((option) {
              final selected = option.url == (_selectedQualityUrl ?? widget.url);

              return ListTile(
                title: Text(option.label),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(option.url),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selectedUrl == null) return;
    if (selectedUrl == (_selectedQualityUrl ?? widget.url)) return;

    await _switchQuality(selectedUrl);
  }

  Future<void> _switchQuality(String nextUrl) async {
    final oldController = _controller;
    final wasPlaying = oldController?.value.isPlaying ?? widget.autoplay;
    final oldPosition = oldController?.value.position ?? Duration.zero;

    if (mounted) {
      setState(() {
        _isQualityLoading = true;
      });
    }

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(nextUrl));
      await controller.initialize().timeout(_initializeTimeout);
      await controller.setLooping(false);
      controller.addListener(_onControllerChanged);

      final duration = controller.value.duration;
      var targetPosition = oldPosition;

      if (duration > Duration.zero && targetPosition > duration) {
        targetPosition = duration;
      }

      if (widget.allowSeeking && targetPosition > Duration.zero) {
        await controller.seekTo(targetPosition);
      }

      if (wasPlaying) {
        await controller.play();
      }

      final previousController = _controller;
      _controller = controller;
      _selectedQualityUrl = nextUrl;
      _state = HlsPlayerState.playing;
      _error = null;

      if (previousController != null) {
        previousController.removeListener(_onControllerChanged);
        await previousController.dispose();
      }

      _syncPositionFromController();
      _startPositionTimer();

      if (mounted) {
        setState(() {
          _isQualityLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isQualityLoading = false;
        _error = 'Не удалось переключить качество: $e';
        _state = HlsPlayerState.error;
      });
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    double size = 16,
    double buttonSize = 34,
  }) {
    return Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: size,
          color: Colors.grey.shade200,
        ),
      ),
    );
  }

  Widget _buildVerticalControls(VideoPlayerController controller) {
    final canSeek = _canSeek;
    final displayPosition = _isDraggingSlider && _dragValueMs != null
        ? Duration(milliseconds: _dragValueMs!.round())
        : _position;

    final positionMs = displayPosition.inMilliseconds.toDouble();
    final durationMs = _duration.inMilliseconds.toDouble();
    final safeMax = durationMs <= 0 ? 1.0 : durationMs;
    final safeValue = positionMs.clamp(0.0, safeMax);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canSeek)
            Theme(
              data: Theme.of(context).copyWith(
                sliderTheme: SliderTheme.of(context).copyWith(
                  trackHeight: 1.6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.22),
                  activeTrackColor: Colors.grey.withValues(alpha: 0.62),
                  thumbColor: Colors.grey.shade500,
                  overlayColor: Colors.grey.withValues(alpha: 0.08),
                ),
              ),
              child: Slider(
                value: safeValue,
                min: 0,
                max: safeMax,
                onChangeStart: (_) {
                  setState(() {
                    _isDraggingSlider = true;
                  });
                },
                onChanged: (value) {
                  setState(() {
                    _dragValueMs = value;
                  });
                },
                onChangeEnd: (value) async {
                  setState(() {
                    _isDraggingSlider = false;
                    _dragValueMs = null;
                  });
                  await _seekTo(Duration(milliseconds: value.round()));
                },
              ),
            ),
          if (canSeek)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Text(
                    _formatDuration(displayPosition),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              _buildControlButton(
                icon: controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: _togglePlayPause,
                size: 16,
                buttonSize: 32,
              ),
              const SizedBox(width: 6),
              _buildControlButton(
                icon: Icons.refresh,
                onPressed: _reinitialize,
                size: 15,
                buttonSize: 32,
              ),
              if (_isBuffering || _isQualityLoading) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImmersiveBottomControls(VideoPlayerController controller) {
    final displayPosition = _isDraggingSlider && _dragValueMs != null
        ? Duration(milliseconds: _dragValueMs!.round())
        : _position;

    final positionMs = displayPosition.inMilliseconds.toDouble();
    final durationMs = _duration.inMilliseconds.toDouble();
    final safeMax = durationMs <= 0 ? 1.0 : durationMs;
    final safeValue = positionMs.clamp(0.0, safeMax);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canSeek)
              Theme(
                data: Theme.of(context).copyWith(
                  sliderTheme: SliderTheme.of(context).copyWith(
                    trackHeight: 1.8,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                    inactiveTrackColor:
                        Colors.grey.shade500.withValues(alpha: 0.30),
                    activeTrackColor:
                        Colors.grey.shade300.withValues(alpha: 0.92),
                    thumbColor: Colors.grey.shade500,
                    overlayColor:
                        Colors.grey.shade300.withValues(alpha: 0.12),
                  ),
                ),
                child: Slider(
                  value: safeValue,
                  min: 0,
                  max: safeMax,
                  onChangeStart: (_) {
                    setState(() {
                      _isDraggingSlider = true;
                      _controlsVisible = true;
                    });
                    _controlsHideTimer?.cancel();
                  },
                  onChanged: (value) {
                    setState(() {
                      _dragValueMs = value;
                    });
                  },
                  onChangeEnd: (value) async {
                    setState(() {
                      _isDraggingSlider = false;
                      _dragValueMs = null;
                    });
                    await _seekTo(Duration(milliseconds: value.round()));
                    _restartControlsAutoHide();
                  },
                ),
              ),
            if (_canSeek)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(displayPosition),
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 10.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_canSeek) ...[
                  _buildControlButton(
                    icon: Icons.replay_10,
                    onPressed: () => _seekRelative(const Duration(seconds: -10)),
                    size: 15,
                    buttonSize: 34,
                  ),
                  const SizedBox(width: 8),
                ],
                _buildControlButton(
                  icon:
                      controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  onPressed: _togglePlayPause,
                  size: 16,
                  buttonSize: 34,
                ),
                if (_canSeek) ...[
                  const SizedBox(width: 8),
                  _buildControlButton(
                    icon: Icons.forward_10,
                    onPressed: () => _seekRelative(const Duration(seconds: 10)),
                    size: 15,
                    buttonSize: 34,
                  ),
                ],
                const SizedBox(width: 8),
                _buildControlButton(
                  icon: Icons.refresh,
                  onPressed: _reinitialize,
                  size: 15,
                  buttonSize: 34,
                ),
                if (widget.allowQualitySelection &&
                    _qualityOptions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildControlButton(
                    icon: Icons.high_quality,
                    onPressed: _isQualityLoading ? null : _showQualitySelector,
                    size: 15,
                    buttonSize: 34,
                  ),
                ],
                if (_isBuffering || _isQualityLoading) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.grey.shade300,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlayButton(VideoPlayerController controller) {
    return Center(
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.grey.shade200,
            size: 26,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupportedPlatform) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Playback fallback',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'В этой сборке Linux/Web встроенный HLS player не поддерживается.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Backend playback уже готов. Этот URL можно проверить на Android-сборке:',
              ),
              const SizedBox(height: 8),
              SelectableText(widget.url),
            ],
          ),
        ),
      );
    }

    if (_state == HlsPlayerState.initializing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_state == HlsPlayerState.streamNotReady) {
      return _buildStatusCard(
        title: 'Ожидание live stream',
        message: _error ?? 'HLS playlist ещё не готов.',
        showRetry: true,
      );
    }

    if (_state == HlsPlayerState.error) {
      return _buildStatusCard(
        title: 'Ошибка воспроизведения',
        message: _error ?? 'Не удалось воспроизвести HLS stream.',
        showRetry: true,
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (widget.immersive) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControlsVisibility,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: _buildVideo(controller),
              ),
            ),
            if (_controlsVisible) _buildCenterPlayButton(controller),
            if (_controlsVisible) _buildImmersiveBottomControls(controller),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVideo(controller),
        _buildVerticalControls(controller),
      ],
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _stopPositionTimer();
    _controlsHideTimer?.cancel();
    _initGeneration += 1;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ));

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      controller.dispose();
    }

    super.dispose();
  }
}

enum _InitAttemptResult {
  success,
  streamNotReady,
  error,
  cancelled,
}

class _HlsQualityOption {
  final String label;
  final String url;

  const _HlsQualityOption({
    required this.label,
    required this.url,
  });

  int get sortValue {
    final match = RegExp(r'(\d+)').firstMatch(label);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}