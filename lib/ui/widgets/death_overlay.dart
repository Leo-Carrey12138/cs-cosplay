import 'package:flutter/material.dart';

import '../../app_config.dart';

/// 阵亡页：锁定相机、隐藏开火按钮后全屏显示。
class DeathOverlay extends StatelessWidget {
  const DeathOverlay({
    super.key,
    required this.rank,
    required this.totalPlayers,
    required this.aliveCount,
    required this.onLeave,
  });

  /// 最终排名（可能还在计算中 → null）
  final int? rank;
  final int totalPlayers;

  /// 还活着的人数
  final int aliveCount;

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF0000000),
      child: SafeArea(
        child: Center(
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
                rank == null ? '正在结算名次…' : '最终排名：第 $rank 名',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '本局共 $totalPlayers 人 · 还有 $aliveCount 人存活',
                style: const TextStyle(fontSize: 14, color: Colors.white54),
              ),
              const SizedBox(height: 34),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '相机已锁定，等待其他玩家结束…\n'
                  '等房主点「重置游戏」即可满血复活',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: Colors.white70, height: 1.6),
                ),
              ),
              const SizedBox(height: 30),
              OutlinedButton.icon(
                onPressed: onLeave,
                icon: const Icon(Icons.logout),
                label: const Text('离开房间'),
              ),
              const SizedBox(height: 10),
              Text(
                '（每局扣 ${Cfg.damagePerHit} HP，满 $Cfg.maxHp）',
                style: const TextStyle(fontSize: 11, color: Colors.white30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
