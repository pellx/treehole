import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/post.dart';
import '../services/storage.dart';
import '../theme/app_dimens.dart';
import '../theme/app_colors.dart';
import 'page_physics.dart';

class ImageOverlay extends StatefulWidget {
  final List<PostImage> images;
  final int initialIndex;
  final List<Rect?> thumbRects;
  final List<Uint8List?> thumbnails;

  const ImageOverlay({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.thumbRects,
    required this.thumbnails,
  });

  static OverlayEntry? currentEntry;
  static void Function()? _onClose;
  static void closeCurrent() => _onClose?.call();

  /// 预览开/关状态。承载预览的页面把它作为 LivePopScope 的
  /// recomputeTrigger 使用：预览打开期间返回手势/返回键被拦截为「先关预览」，
  /// 不依赖页面重建时机
  static final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);

  /// 从图片字节解析尺寸（仅读文件头，不做完整像素解码），
  /// 作为 photo_view customChild 的 childSize
  static Future<Size?> resolveImageSize(Uint8List bytes) async {
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        bytes,
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final Size size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> downloadPng(String fileName) async {
    try {
      final res = await http
          .get(Uri.parse('https://www.leisure.xin:33433/upload/$fileName'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  @override
  State<ImageOverlay> createState() => _ImageOverlayState();
}

class _ImageOverlayState extends State<ImageOverlay>
    with TickerProviderStateMixin {
  late AnimationController _animCtrl;
  late AnimationController _actionBarCtrl;
  late AnimationController _dotsCtrl;
  late AnimationController _saveToastCtrl;
  late Animation<double> _expandAnim;
  late Animation<Color?> _bgAnim;
  int _currentIndex = 0;
  bool _shown = false;
  bool _showActionBar = false;
  bool _saving = false;

  final Map<int, Uint8List?> _pngCache = {};
  final Set<int> _loading = {};
  final Map<int, AnimationController> _fadeCtrls = {};
  final List<AnimationController> _pendingFades = [];
  final Map<int, bool> _pngReady = {};
  final Map<int, Size> _childSizes = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: AppDimens.imageExpandMs),
    );
    _expandAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _bgAnim = ColorTween(
      begin: Colors.transparent,
      end: Colors.black,
    ).animate(_expandAnim);
    _actionBarCtrl =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: AppDimens.actionBarAnimMs),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: AppDimens.pageIndicatorFadeMs),
    );
    _saveToastCtrl =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: AppDimens.saveToastAnimMs),
        )..addListener(() {
          if (mounted) setState(() {});
        });

    _animCtrl.forward().then((_) {
      setState(() => _shown = true);
      for (final fc in _pendingFades) {
        if (mounted) fc.forward();
      }
      _pendingFades.clear();
    });
    _dotsCtrl.forward();
    _animCtrl.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        ImageOverlay.currentEntry?.remove();
        ImageOverlay.currentEntry = null;
        ImageOverlay._onClose = null;
        ImageOverlay.isOpen.value = false;
      }
    });
    _animCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    ImageOverlay._onClose = _close;
    ImageOverlay.isOpen.value = true;

    // 预加载相邻图
    if (widget.initialIndex + 1 < widget.images.length) {
      _loadPng(widget.initialIndex + 1);
    }
    if (widget.initialIndex > 0) {
      _loadPng(widget.initialIndex - 1);
    }
  }

  @override
  void dispose() {
    for (final c in _fadeCtrls.values) {
      c.dispose();
    }
    _pendingFades.clear();
    _animCtrl.dispose();
    _actionBarCtrl.dispose();
    _dotsCtrl.dispose();
    _saveToastCtrl.dispose();
    super.dispose();
  }

  void _loadPng(int index) {
    if (_pngCache.containsKey(index) && _pngCache[index] != null) return;
    if (_loading.contains(index)) return;
    _loading.add(index);

    final fileName = widget.images[index].fileName;

    PostStorage.getPng(fileName).then((cached) {
      if (!mounted) {
        _loading.remove(index);
        return;
      }
      _loading.remove(index);
      if (cached != null) {
        _startPngFade(index, cached);
        return;
      }
      _loading.add(index);
      ImageOverlay.downloadPng(fileName).then((bytes) {
        if (!mounted) {
          _loading.remove(index);
          return;
        }
        _loading.remove(index);
        if (bytes != null) {
          PostStorage.savePng(fileName, bytes);
          _startPngFade(index, bytes);
        }
      });
    });
  }

  void _startPngFade(int index, Uint8List bytes) {
    _fadeCtrls[index]?.dispose();
    final fc = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: AppDimens.imageFadeMs),
    );
    _fadeCtrls[index] = fc;
    fc.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _pngCache[index] = bytes;
      _pngReady[index] = false;
    });
    _resolveChildSize(index, bytes);
  }

  void _resolveChildSize(int index, Uint8List bytes) {
    if (_childSizes.containsKey(index)) return;
    ImageOverlay.resolveImageSize(bytes).then((size) {
      if (!mounted || size == null) return;
      setState(() => _childSizes[index] = size);
    });
  }

  void _onPngFrameReady(int index) {
    if (_pngReady[index] == true) return;
    _pngReady[index] = true;
    final fc = _fadeCtrls[index];
    if (fc == null) return;
    if (_shown) {
      fc.forward();
    } else {
      _pendingFades.add(fc);
    }
  }

  Future<void> _saveImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final index = _currentIndex;
      final fileName = widget.images[index].fileName;
      Uint8List? bytes = _pngCache[index];
      bytes ??= await ImageOverlay.downloadPng(fileName);
      if (bytes != null) {
        await Gal.putImageBytes(bytes, name: fileName);
        setState(() {
          _showActionBar = false;
          _actionBarCtrl.reverse();
        });
        _showSaveToast();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    final index = _currentIndex;
    final fileName = widget.images[index].fileName;
    Uint8List? bytes = _pngCache[index];
    bytes ??= await ImageOverlay.downloadPng(fileName);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: '来自树通');
  }

  void _showSaveToast() {
    _saveToastCtrl.forward().then((_) {
      Future.delayed(Duration(milliseconds: AppDimens.saveToastDurationMs), () {
        if (mounted) _saveToastCtrl.reverse();
      });
    });
  }

  void _close() {
    if (!mounted) return;
    if (_animCtrl.status == AnimationStatus.reverse ||
        _animCtrl.status == AnimationStatus.dismissed) {
      return;
    }
    _shown = false;
    setState(() {});
    _showActionBar = false;
    _dotsCtrl.reverse();
    _actionBarCtrl.duration = Duration(
      milliseconds: AppDimens.actionBarCloseAnimMs,
    );
    _actionBarCtrl.reverse();
    _animCtrl.reverse();
  }

  Rect _fromRect() {
    final r = widget.thumbRects.length > _currentIndex
        ? widget.thumbRects[_currentIndex]
        : null;
    return r ?? widget.thumbRects[widget.initialIndex]!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final screenSize = MediaQuery.of(context).size;
    final fullRect = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    final startR = _fromRect();

    final progress = _expandAnim.value;
    final rect = Rect.lerp(startR, fullRect, progress)!;

    // 本组件是 OverlayEntry（无 ModalRoute 祖先），PopScope 在此不生效；
    // 返回键/返回手势的拦截由承载页监听 ImageOverlay.isOpen 后以 PopScope 完成
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_showActionBar) {
          setState(() => _showActionBar = false);
          _actionBarCtrl.reverse();
        } else {
          _close();
        }
      },
      onLongPress: () {
        setState(() => _showActionBar = true);
        _actionBarCtrl.duration = Duration(
          milliseconds: AppDimens.actionBarAnimMs,
        );
        _actionBarCtrl.forward();
      },
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: _bgAnim.value)),
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: ClipRRect(
              borderRadius: progress < 1
                  ? BorderRadius.circular(4 * (1 - progress))
                  : BorderRadius.zero,
              child: _buildContent(),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: AppDimens.pageIndicatorBottomMargin,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _dotsCtrl,
                child: Center(
                  child: Wrap(
                    spacing: AppDimens.pageIndicatorDotGap,
                    runSpacing: 0,
                    children: List.generate(widget.images.length, (i) {
                      final active = i == _currentIndex;
                      return Container(
                        width: AppDimens.pageIndicatorDotSize,
                        height: AppDimens.pageIndicatorDotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.common.overlayPageDot.withValues(
                            alpha: active
                                ? AppDimens.overlayPageDotActiveOpacity
                                : AppDimens.overlayPageDotInactiveOpacity,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          if (_showActionBar || _actionBarCtrl.value > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: _showActionBar
                  ? -AppDimens.actionBarHeight +
                        _actionBarCtrl.value *
                            (AppDimens.actionBarBottomMargin +
                                AppDimens.actionBarHeight)
                  : AppDimens.actionBarBottomMargin,
              child: Opacity(
                opacity: _actionBarCtrl.value,
                child: Center(
                  child: Container(
                    height: AppDimens.actionBarHeight,
                    decoration: BoxDecoration(
                      color: colors.common.overlayActionBarBg,
                      borderRadius: BorderRadius.circular(
                        AppDimens.actionBarRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: AppDimens.actionBarBtnGap),
                        IconButton(
                          icon: _saving
                              ? SizedBox(
                                  width: AppDimens.actionBarBtnSize,
                                  height: AppDimens.actionBarBtnSize,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.common.overlayIcon,
                                  ),
                                )
                              : Icon(
                                  Icons.download,
                                  size: AppDimens.actionBarBtnSize,
                                  color: colors.common.overlayIcon,
                                ),
                          onPressed: _saveImage,
                        ),
                        SizedBox(width: AppDimens.actionBarBtnGap),
                        IconButton(
                          icon: Icon(
                            Icons.share,
                            size: AppDimens.actionBarBtnSize,
                            color: colors.common.overlayIcon,
                          ),
                          onPressed: _shareImage,
                        ),
                        SizedBox(width: AppDimens.actionBarBtnGap),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_saveToastCtrl.value > 0)
            Positioned(
              bottom: AppDimens.saveToastBottomMargin,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: _saveToastCtrl.value,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppDimens.saveToastHPadding,
                        vertical: AppDimens.saveToastVPadding,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(
                          AppDimens.saveToastRadius,
                        ),
                      ),
                      child: Text(
                        '已保存至相册',
                        style: TextStyle(
                          fontSize: AppDimens.saveToastFontSize,
                          color: colors.common.overlayIcon,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return PhotoViewGallery.builder(
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      scrollPhysics: FastPageScrollPhysics(
        parent: BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
        ),
      ),
      pageController: PageController(initialPage: widget.initialIndex),
      itemCount: widget.images.length,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
        _loadPng(index);
        if (index + 1 < widget.images.length) _loadPng(index + 1);
        if (index > 0) _loadPng(index - 1);
      },
      builder: (context, index) {
        _loadPng(index);
        final png = _pngCache[index];
        final hasPng = png != null;
        final thumb = widget.thumbnails.length > index
            ? widget.thumbnails[index]
            : null;
        final fadeCtrl = _fadeCtrls[index];
        final childSize = _childSizes[index];

        return PhotoViewGalleryPageOptions.customChild(
          // 不传 childSize 时 photo_view 以视口尺寸兜底，
          // contained 与 covered 都会算成 1.0，双击缩放等于原地不动
          childSize: childSize,
          // 双击循环：非原始显示状态（含捏合缩放中）一律恢复原始大小，
          // 原始大小则放大到铺满屏幕
          scaleStateCycle: (actual) => actual == PhotoViewScaleState.initial
              ? PhotoViewScaleState.covering
              : PhotoViewScaleState.initial,
          child: SizedBox(
            width: childSize?.width,
            height: childSize?.height,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (hasPng)
                  Align(
                    child: Image.memory(
                      png,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      frameBuilder:
                          (context, child, frame, wasSynchronouslyLoaded) {
                            if (frame != null) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _onPngFrameReady(index);
                              });
                            }
                            return child;
                          },
                    ),
                  ),
                if (thumb != null)
                  Align(
                    child: Opacity(
                      opacity: hasPng
                          ? (fadeCtrl != null ? 1 - fadeCtrl.value : 0)
                          : 1,
                      child: Image.memory(
                        thumb,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                if (thumb == null && !hasPng)
                  const Center(child: SizedBox.shrink()),
              ],
            ),
          ),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        );
      },
    );
  }
}
