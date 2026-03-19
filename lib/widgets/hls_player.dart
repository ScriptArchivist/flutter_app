import 'dart:async';

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

  const HlsPlayer({
    super.key,
    required this.url,
    this.autoplay = true,
    this.immersive = false,
  });

  @override
  State<HlsPlayer> createState() => _HlsPlayerState();
}

class _HlsPlayerState extends State<HlsPlayer> {
  static const int _maxInitAttempts = 5;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _initializeTimeout = Duration(seconds: 20);

  VideoPlayerController? _controller;

  HlsPlayerState _state = HlsPlayerState.initializing;
  String? _error;
  bool _unsupportedPlatform = false;

  int _initAttempt = 0;
  int _initGeneration = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _applyImmersiveMode();
    _startInitialization();
  }

  @override
  void didUpdateWidget(covariant HlsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      _reinitialize();
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

  Future<void> _applyImmersiveMode() async {
    if (kIsWeb) return;

    if (widget.immersive) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
      if (!mounted || generation != _initGeneration) return _InitAttemptResult.cancelled;
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
      if (!mounted || generation != _initGeneration) return _InitAttemptResult.cancelled;

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
      controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

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

    if (value.isInitialized) {
      if (_state != HlsPlayerState.playing) {
        _setPlayerState(HlsPlayerState.playing);
      } else {
        setState(() {});
      }
    }
  }

  Widget _buildVideo(VideoPlayerController controller) {
    if (widget.immersive) {
      final size = controller.value.size;
      final width = size.width <= 0 ? 16.0 : size.width;
      final height = size.height <= 0 ? 9.0 : size.height;

      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
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

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
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
      return Stack(
        children: [
          Positioned.fill(
            child: _buildVideo(controller),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: IconButton(
                    onPressed: _togglePlayPause,
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: IconButton(
                    onPressed: _reinitialize,
                    icon: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVideo(controller),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            ),
            IconButton(
              onPressed: _reinitialize,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _initGeneration += 1;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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