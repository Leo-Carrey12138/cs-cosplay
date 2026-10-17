import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';

/// 受击表现层：全屏红光闪烁 2 次（约 1 秒）+ 屏幕中央大字"你被击中了！"
/// 震动和音效由 GameScreen 负责（这里只管画面）。
class DamageFlashLayer extends StatefulWidget {
  const DamageFlashLayer({super.key, required this.damageStream});

  final Stream<int> damageStream;

  @override
  State<DamageFlashLayer> createState() => _DamageFlashLayerState();
}

class _DamageFlashLayerState extends State<DamageFlashLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  StreamSubscription<int>? _subscription;
  Timer? _bannerTimer;
  bool _showBanner = false;
  int _lastDamage = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Cfg.redFlashDuration,
    );
    _subscription = widget.damageStream.listen((amount) {
      _lastDamage = amount;
      _trigger();
    });
  }

  void _trigger() {
    _controller.forward(from: 0); // 重头播：连续被打也能立刻响应
    _bannerTimer?.cancel();
    if (!_showBanner && mounted) {
      setState(() => _showBanner = true);
    }
    _bannerTimer = Timer(Cfg.damageBannerDuration, () {
      if (mounted) setState(() => _showBanner = false);
    });
  }

  /// 把 0→1 的线性进度切成 2 次脉冲
  double get _flashOpacity {
    final t = (_controller.value * 2) % 1.0;
    final pulse = t < 0.5 ? t * 2 : (1 - t) * 2;
    return pulse * 0.45;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bannerTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final opacity = _flashOpacity;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (opacity > 0.001)
                Container(
                  color: const Color(0xFFFF0000)
                      .withAlpha((opacity * 255).round().clamp(0, 255).toInt()),
                ),
              if (_showBanner)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xCC7F0000),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFFF5252), width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          '你被击中了！',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        if (_lastDamage > 0)
                          Text(
                            '-$_lastDamage HP',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFCDD2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
