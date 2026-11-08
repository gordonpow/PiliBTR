import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Cold-start splash animation drawn above the home page.
///
/// Logo scales in, "PiliBTR" fades in and slides up, then the whole overlay
/// fades out. Tap or back gesture skips with a short fade out.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onFinished});

  final VoidCallback onFinished;

  static const _logo = 'assets/images/logo/logo_2.png';

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;
  late final Animation<double> _overlayFade;

  bool _skipping = false;
  bool _finished = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _skipController.value = 0; // create now, not lazily in dispose
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1400),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
    Animation<double> seg(double begin, double end, Curve curve) =>
        CurvedAnimation(
          parent: _controller,
          curve: Interval(begin, end, curve: curve),
        );
    _logoScale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(seg(0, 0.45, Curves.easeOutCubic));
    _logoFade = seg(0, 0.45, Curves.easeOut);
    _textFade = seg(0.3, 0.65, Curves.easeOut);
    _textSlide = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(seg(0.3, 0.65, Curves.easeOutCubic));
    _overlayFade = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(seg(0.8, 1.0, Curves.easeIn));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Decode the logo first so it does not pop in; only the background shows
    // until then.
    precacheImage(const AssetImage(SplashOverlay._logo), context).whenComplete(
      () {
        if (mounted && !_skipping) _controller.forward();
      },
    );
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  void _skip() {
    if (_skipping || _finished) return;
    _skipping = true;
    _controller.stop();
    _skipFadeFrom = _overlayFade.value;
    _skipController.forward();
  }

  double _skipFadeFrom = 1;

  late final AnimationController _skipController =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });

  @override
  void dispose() {
    _controller.dispose();
    _skipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 不論深淺色模式都用黑底，與 pubspec.yaml 的 flutter_native_splash 一致。
    const bg = Color(0xFF000000);
    const fg = Colors.white;
    final logoWidth = math.min(MediaQuery.sizeOf(context).width * 0.3, 160.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _skip(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: Listenable.merge([_controller, _skipController]),
          builder: (context, _) {
            final opacity = _skipping
                ? _skipFadeFrom * (1 - _skipController.value)
                : _overlayFade.value;
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: ColoredBox(
                color: bg,
                child: SizedBox.expand(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: _logoFade.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Image.asset(
                            SplashOverlay._logo,
                            width: logoWidth,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Opacity(
                        opacity: _textFade.value,
                        child: Transform.translate(
                          offset: Offset(0, _textSlide.value),
                          child: Text(
                            'PiliBTR',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: fg,
                                  decoration: TextDecoration.none,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
