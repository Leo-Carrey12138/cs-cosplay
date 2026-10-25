import 'package:flutter/material.dart';

import '../theme/csgo_theme.dart';

/// 右下角开火按钮。
/// 就绪时红色实心（危险/开火语义），冷却时灰化并用圆环显示剩余进度。
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
    final bool active = enabled && !cooling;
    final Color ring = cooling
        ? CsColors.accentDim
        : active
            ? CsColors.danger
            : CsColors.borderStrong;
    final Color face = !enabled
        ? CsColors.panelDeep
        : active
            ? const Color(0xFFA81F25)
            : CsColors.panelRaised;
    final Color label = active ? Colors.white : CsColors.textMuted;

    return Semantics(
      button: true,
      enabled: active,
      label: cooling ? '开火冷却中' : (active ? '开火' : '开火不可用'),
      child: SizedBox(
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
                  strokeWidth: 3.2,
                  backgroundColor: CsColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(CsColors.accent),
                ),
              ),
            // 外层细环
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CsColors.panelDeep,
                border: Border.all(
                  color: ring.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: active ? onPressed : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: face,
                    border: Border.all(color: ring, width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        cooling ? Icons.hourglass_bottom : Icons.gps_fixed,
                        color: label,
                        size: 24,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cooling ? '冷却' : (active ? '开火' : '待机'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: label,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        cooling ? 'RELOAD' : (active ? 'FIRE' : 'STANDBY'),
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: active
                              ? const Color(0xCCFFFFFF)
                              : CsColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
