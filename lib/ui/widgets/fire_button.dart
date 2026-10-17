import 'package:flutter/material.dart';

/// 右下角开火按钮。
/// 冷却期间灰化，并用圆环显示剩余冷却进度。
class FireButton extends StatelessWidget {
  const FireButton({
    super.key,
    required this.onPressed,
    required this.cooling,
    required this.cooldownProgress,
    this.enabled = true,
  });

  final VoidCallback onPressed;

  /// 是否正在冷却
  final bool cooling;

  /// 剩余冷却进度 1.0 → 0.0
  final double cooldownProgress;

  /// 阵亡/未就绪时整体不可用
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !cooling;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 冷却圆环
          if (cooling)
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                value: cooldownProgress.clamp(0.0, 1.0).toDouble(),
                strokeWidth: 5,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
              ),
            ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: active ? onPressed : null,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active
                      ? const RadialGradient(
                          colors: <Color>[Color(0xFFFF5252), Color(0xFFB71C1C)],
                        )
                      : null,
                  color: active ? null : const Color(0xFF3A3A3A),
                  border: Border.all(
                    color: active ? Colors.white70 : Colors.white24,
                    width: 2,
                  ),
                  boxShadow: active
                      ? <BoxShadow>[
                          BoxShadow(
                            color: const Color(0xFFFF5252).withAlpha(90),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      cooling ? Icons.hourglass_bottom : Icons.gps_fixed,
                      color: active ? Colors.white : Colors.white38,
                      size: 26,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cooling ? '冷却' : '开火',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: active ? Colors.white : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
