import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
  VideoPlayerController? _controller;
  String? _error;
  bool _unsupportedPlatform = false;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant HlsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      _reinitialize();
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

  Future<void> _reinitialize() async {
    final oldController = _controller;
    _controller = null;

    if (mounted) {
      setState(() {
        _error = null;
        _unsupportedPlatform = false;
        _initializing = true;
      });
    }

    await oldController?.dispose();
    await _init();
  }

  Future<void> _init() async {
    if (_shouldUseFallback) {
      if (!mounted) return;
      setState(() {
        _unsupportedPlatform = true;
        _initializing = false;
      });
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );

      await controller.initialize().timeout(const Duration(seconds: 20));
      await controller.setLooping(false);

      controller.addListener(_onControllerChanged);

      if (widget.autoplay) {
        await controller.play();
      }

      if (!mounted) {
        controller.removeListener(_onControllerChanged);
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _error = null;
        _unsupportedPlatform = false;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Player init failed: $e';
        _initializing = false;
      });
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final controller = _controller;
    if (controller == null) return;

    final value = controller.value;
    if (value.hasError) {
      setState(() {
        _error = value.errorDescription ?? 'Playback error';
      });
      return;
    }

    setState(() {});
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
      child: VideoPlayer(controller),
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

    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              SelectableText(widget.url),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reinitialize,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
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
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }
}