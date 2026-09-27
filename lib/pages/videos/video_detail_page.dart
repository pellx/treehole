import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/video_item.dart';
import '../../services/device_credential_store.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../services/video_api.dart';
import '../../widgets/app_app_bar.dart';
import '../account/register_page.dart';

class VideoDetailPage extends StatefulWidget {
  final int videoId;

  const VideoDetailPage({super.key, required this.videoId});

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  final _text = TextEditingController();
  final _enabled = ValueNotifier<bool>(true);
  final _surfaces = <DanmakuController<int>>{};
  VideoItem? _video;
  VideoPlayerController? _player;
  ChewieController? _chewie;
  Timer? _timer;
  List<VideoDanmaku> _comments = const [];
  int _windowStart = -1;
  int _windowEnd = -1;
  int _nextComment = 0;
  int _lastMs = -1;
  int _windowGeneration = 0;
  bool _windowLoading = false;
  bool _wasPlaying = false;
  bool _sending = false;
  bool _loading = true;
  String? _error;
  String _quality = '自动';
  double? _heldSpeed;
  double _danmakuSpeed = 1;
  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final video = await VideoApi.detail(widget.videoId);
      if (!mounted) return;
      _video = video;
      await _openSource(video.playbackUrl, autoPlay: false);
      if (!mounted) return;
      _timer ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _tick(),
      );
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '视频加载失败，请重试';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSource(
    Uri url, {
    Duration resume = Duration.zero,
    required bool autoPlay,
    double speed = 1,
  }) async {
    final next = VideoPlayerController.networkUrl(url);
    try {
      await next.initialize();
      if (resume > Duration.zero) await next.seekTo(resume);
      await next.setPlaybackSpeed(speed);
      if (!mounted) {
        await next.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: next,
        autoPlay: false,
        aspectRatio: next.value.aspectRatio > 0
            ? next.value.aspectRatio
            : 16 / 9,
        deviceOrientationsOnEnterFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: const [DeviceOrientation.portraitUp],
        overlay: _PlayerOverlay(
          enabled: _enabled,
          onReady: _registerSurface,
          onRemoved: _removeSurface,
          onDoubleTap: _togglePlay,
          onDragStart: () => _dragDx = 0,
          onDragUpdate: (dx) => _dragDx += dx,
          onDragEnd: _finishDrag,
          onLongPressStart: _holdFast,
          onLongPressEnd: _releaseFast,
        ),
        additionalOptions: (context) => [
          OptionItem(
            iconData: Icons.subtitles_outlined,
            title: _enabled.value ? '关闭弹幕' : '开启弹幕',
            onTap: (context) {
              Navigator.pop(context);
              _enabled.value = !_enabled.value;
              _resetComments();
            },
          ),
          OptionItem(
            iconData: Icons.high_quality_outlined,
            title: '清晰度：$_quality',
            onTap: (context) {
              Navigator.pop(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showQualityPicker(this.context);
              });
            },
          ),
        ],
      );
      final oldPlayer = _player;
      final oldChewie = _chewie;
      _player = next;
      _chewie = chewie;
      _resetComments();
      setState(() {});
      if (autoPlay) await next.play();
      oldChewie?.dispose();
      await oldPlayer?.dispose();
    } catch (_) {
      await next.dispose();
      rethrow;
    }
  }

  void _registerSurface(DanmakuController<int> controller) {
    _surfaces.add(controller);
    final speed = _player?.value.playbackSpeed ?? 1;
    controller.updateOption(
      controller.option.copyWith(
        duration: 10 / speed,
        staticDuration: 5 / speed,
      ),
    );
    if (!(_player?.value.isPlaying ?? false)) controller.pause();
  }

  void _removeSurface(DanmakuController<int> controller) =>
      _surfaces.remove(controller);

  void _resetComments() {
    _windowGeneration++;
    _windowStart = -1;
    _windowEnd = -1;
    _comments = const [];
    _nextComment = 0;
    _lastMs = -1;
    for (final surface in _surfaces) {
      surface.clear();
    }
  }

  void _tick() {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    final speed = player.value.playbackSpeed;
    if ((speed - _danmakuSpeed).abs() > 0.01) {
      _danmakuSpeed = speed;
      for (final surface in _surfaces) {
        surface.updateOption(
          surface.option.copyWith(
            duration: 10 / speed,
            staticDuration: 5 / speed,
          ),
        );
      }
    }
    final playing = player.value.isPlaying;
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      for (final surface in _surfaces) {
        if (playing) {
          surface.resume();
        } else {
          surface.pause();
        }
      }
    }
    final ms = player.value.position.inMilliseconds;
    if (_lastMs >= 0 && (ms < _lastMs - 400 || ms > _lastMs + 1500)) {
      for (final surface in _surfaces) {
        surface.clear();
      }
      _nextComment = _comments.indexWhere((item) => item.timeMs >= ms);
      if (_nextComment < 0) _nextComment = _comments.length;
    }
    _lastMs = ms;
    if (ms < _windowStart || ms >= _windowEnd) {
      _fetchWindow(ms);
      return;
    }
    if (!_enabled.value) {
      while (_nextComment < _comments.length &&
          _comments[_nextComment].timeMs <= ms) {
        _nextComment++;
      }
      return;
    }
    if (!playing) return;
    while (_nextComment < _comments.length &&
        _comments[_nextComment].timeMs <= ms) {
      final item = _comments[_nextComment++];
      for (final surface in _surfaces) {
        surface.addDanmaku(DanmakuContentItem<int>(item.text, extra: item.id));
      }
    }
  }

  Future<void> _fetchWindow(int ms) async {
    if (_windowLoading) return;
    final start = (ms ~/ 60000) * 60000;
    final generation = ++_windowGeneration;
    _windowLoading = true;
    try {
      final comments = await VideoApi.danmaku(
        widget.videoId,
        start,
        start + 60000,
      );
      if (!mounted || generation != _windowGeneration) return;
      _comments = comments;
      _windowStart = start;
      _windowEnd = start + 60000;
      final current = _player?.value.position.inMilliseconds ?? ms;
      _nextComment = comments.indexWhere((item) => item.timeMs >= current);
      if (_nextComment < 0) _nextComment = comments.length;
    } catch (_) {
      _windowStart = start;
      _windowEnd = start + 60000;
    } finally {
      _windowLoading = false;
    }
  }

  void _togglePlay() {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      player.pause();
    } else {
      player.play();
    }
  }

  void _finishDrag() {
    final player = _player;
    if (player == null || _dragDx.abs() < 12) return;
    final delta = Duration(
      milliseconds: (_dragDx * 60000 / MediaQuery.sizeOf(context).width)
          .round(),
    );
    final target = player.value.position + delta;
    final duration = player.value.duration;
    player.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > duration
          ? duration
          : target,
    );
    _resetComments();
  }

  void _holdFast() {
    final player = _player;
    if (player == null) return;
    _heldSpeed ??= player.value.playbackSpeed;
    player.setPlaybackSpeed(2);
    for (final surface in _surfaces) {
      surface.updateOption(surface.option.copyWith(duration: 5));
    }
  }

  void _releaseFast() {
    final player = _player;
    final speed = _heldSpeed;
    if (player == null || speed == null) return;
    _heldSpeed = null;
    player.setPlaybackSpeed(speed);
    for (final surface in _surfaces) {
      surface.updateOption(surface.option.copyWith(duration: 10));
    }
  }

  Future<void> _showQualityPicker(BuildContext context) async {
    final video = _video;
    if (video == null) return;
    final options = [
      VideoQuality(label: '自动', url: video.playbackUrl),
      ...video.qualities,
    ];
    final picked = await showModalBottomSheet<VideoQuality>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (item) => ListTile(
                  title: Text(item.label),
                  trailing: item.label == _quality
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, item),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked == null || picked.label == _quality || !mounted) return;
    final player = _player;
    final wasPlaying = player?.value.isPlaying ?? false;
    final wasFullScreen = _chewie?.isFullScreen ?? false;
    final position = player?.value.position ?? Duration.zero;
    final speed = player?.value.playbackSpeed ?? 1;
    if (wasFullScreen) _chewie?.exitFullScreen();
    try {
      await _openSource(
        picked.url,
        resume: position,
        autoPlay: wasPlaying,
        speed: speed,
      );
      if (!mounted) return;
      setState(() => _quality = picked.label);
      if (wasFullScreen) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _chewie?.enterFullScreen(),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(const SnackBar(content: Text('切换清晰度失败')));
      }
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    if (!PostStorage.isRegistered()) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const RegisterPage()));
      return;
    }
    setState(() => _sending = true);
    try {
      if (!await SessionService.instance.ensureSession()) throw Exception();
      final id = await DeviceCredentialStore.getSessionId();
      final secret = await DeviceCredentialStore.getSessionSecret();
      if (id == null || secret == null) throw Exception();
      final item = await VideoApi.sendDanmaku(
        widget.videoId,
        _player?.value.position.inMilliseconds ?? 0,
        text,
        sessionId: id,
        sessionSecret: secret,
      );
      _text.clear();
      if (_enabled.value) {
        for (final surface in _surfaces) {
          surface.addDanmaku(
            DanmakuContentItem<int>(item.text, selfSend: true, extra: item.id),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('发送失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chewie?.dispose();
    _player?.dispose();
    _enabled.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return AppScaffold(
      title: video?.title ?? '视频',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: TextButton(onPressed: _load, child: Text(_error!)),
            )
          : ListView(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _chewie == null
                      ? const SizedBox()
                      : Chewie(controller: _chewie!),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    video?.title ?? '',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _enabled,
                  builder: (context, enabled, _) => SwitchListTile(
                    title: const Text('弹幕'),
                    value: enabled,
                    onChanged: (value) {
                      _enabled.value = value;
                      _resetComments();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          maxLength: 100,
                          decoration: const InputDecoration(hintText: '发送弹幕'),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton(
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  final ValueNotifier<bool> enabled;
  final ValueChanged<DanmakuController<int>> onReady;
  final ValueChanged<DanmakuController<int>> onRemoved;
  final VoidCallback onDoubleTap;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  const _PlayerOverlay({
    required this.enabled,
    required this.onReady,
    required this.onRemoved,
    required this.onDoubleTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, value, _) => value
            ? IgnorePointer(
                child: _DanmakuSurface(onReady: onReady, onRemoved: onRemoved),
              )
            : const SizedBox(),
      ),
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: onDoubleTap,
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onLongPressStart: (_) => onLongPressStart(),
        onLongPressEnd: (_) => onLongPressEnd(),
      ),
    ],
  );
}

class _DanmakuSurface extends StatefulWidget {
  final ValueChanged<DanmakuController<int>> onReady;
  final ValueChanged<DanmakuController<int>> onRemoved;

  const _DanmakuSurface({required this.onReady, required this.onRemoved});

  @override
  State<_DanmakuSurface> createState() => _DanmakuSurfaceState();
}

class _DanmakuSurfaceState extends State<_DanmakuSurface> {
  DanmakuController<int>? _controller;

  @override
  void dispose() {
    if (_controller != null) widget.onRemoved(_controller!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DanmakuScreen<int>(
    createdController: (controller) {
      _controller = controller;
      widget.onReady(controller);
    },
    option: const DanmakuOption(fontSize: 16, area: 0.65, duration: 10),
  );
}
