import 'package:flutter/material.dart';

import '../../app_config.dart';

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
      color: const Color(0xF0000000),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.dangerous, size: 78, color: Color(0xFFFF5252)),
                const SizedBox(height: 10),
                const Text(
                  '你已阵亡',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF5252),
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  seconds > 0 ? '$seconds 秒后重新部署' : '正在重新部署…',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF5252),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    '复活后满血，并获得 '
                    '${Cfg.respawnInvincible.inSeconds} 秒保护',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white70, height: 1.6),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onLeave,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size(140, 48),
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('离开房间'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '（每次命中扣 ${Cfg.damagePerHit} HP，满 ${Cfg.maxHp}）',
                  style: TextStyle(fontSize: 11, color: Colors.white30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
