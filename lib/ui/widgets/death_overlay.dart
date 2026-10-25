import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../theme/csgo_theme.dart';

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
                  const SizedBox(height: 20),
                  CsgoPanel(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      children: <Widget>[
                        const Text(
                          'FINAL RANK // 最终排名',
                          style: TextStyle(
                            color: CsColors.textMuted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rank == null ? '结算中…' : '第 $rank 名',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: CsColors.accent,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Divider(color: CsColors.border, height: 1),
                        const SizedBox(height: 10),
                        Text(
                          '本局 $totalPlayers 人 · 还有 $aliveCount 人存活',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: CsColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const CsgoPanel(
                    color: CsColors.panelDeep,
                    padding: EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: CsColors.accentDim,
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '相机已锁定，等待其他玩家结束…\n'
                            '等房主点「重置游戏」即可满血复活',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: CsColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: onLeave,
                    icon: const Icon(Icons.logout, size: 17),
                    label: const Text('离开房间'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '每局扣 ${Cfg.damagePerHit} HP · 满 ${Cfg.maxHp} HP',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      color: CsColors.textMuted,
                    ),
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
