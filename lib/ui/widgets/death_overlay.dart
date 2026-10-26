import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../theme/csgo_theme.dart';

/// 阵亡页：锁定相机、隐藏开火按钮后全屏显示，5 秒倒计时后自动复活。
class DeathOverlay extends StatelessWidget {
  const DeathOverlay({
    super.key,
    required this.remainingMs,
    required this.totalMs,
    required this.onLeave,
  });

  /// 距离自动复活还剩多少毫秒（服务器时间基准）
  final int remainingMs;

  /// 复活总等待时长（用于进度条）
  final int totalMs;

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final total = totalMs <= 0 ? 1 : totalMs;
    final remaining = remainingMs.clamp(0, total);
    final progress = (1 - remaining / total).clamp(0.0, 1.0).toDouble();
    final seconds = (remaining / 1000).ceil();

    return Container(
      color: const Color(0xF2171A16),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Align(
                    alignment: Alignment.center,
                    child: CsgoTag(label: 'K.I.A.', color: CsColors.danger),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '你已阵亡',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: CsColors.danger,
                      letterSpacing: 8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    seconds > 0 ? '$seconds 秒后重新部署' : '正在重新部署…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: CsColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: CsColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        CsColors.danger,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  CsgoPanel(
                    color: CsColors.panelDeep,
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    child: Column(
                      children: <Widget>[
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.shield_outlined,
                              size: 16,
                              color: Color(0xFF40C4FF),
                            ),
                            SizedBox(width: 7),
                            Text(
                              'AUTO REDEPLOY // 自动复活',
                              style: TextStyle(
                                color: Color(0xFF40C4FF),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '复活后满血，并获得 '
                          '${Cfg.respawnInvincible.inSeconds} 秒保护',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            color: CsColors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '每次命中扣 ${Cfg.damagePerHit} HP · 满 ${Cfg.maxHp} HP',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.4,
                            color: CsColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onLeave,
                    icon: const Icon(Icons.logout, size: 17),
                    label: const Text('离开房间'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
