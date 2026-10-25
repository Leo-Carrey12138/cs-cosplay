import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/player.dart';
import '../theme/csgo_theme.dart';

/// 顶部：本房间所有玩家的血条列表（名字 + HP + 阵亡灰显）
class PlayerHpList extends StatelessWidget {
  const PlayerHpList({super.key, required this.players, required this.myId});

  final List<Player> players;
  final String myId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 注意：这里的高度是给横向 ListView 定界用的，卡片内容比它高就会
      // 报 "BOTTOM OVERFLOWED BY x PIXELS"。
      // 卡片内容实测高度 ≈ 48（名字行 ~17 + 4 + 进度条 4 + 3 + HP 文本 ~14），
      // Container 内边距上下各 5、边框上下各 1 → 需要 ≥ 54。
      // 取 64 留出余量，字体放大一档也不会溢出。
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // 外层终端面板已经有 10px 内边距，这里不再叠加，保证血条卡片和
        // 房间号左对齐；3 个玩家时正好铺满，6 个玩家时横向滚动。
        padding: EdgeInsets.zero,
        itemCount: players.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final player = players[index];
          return _PlayerChip(player: player, isMe: player.id == myId);
        },
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.player, required this.isMe});

  final Player player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final bool alive = player.isAlive;
    final double ratio = (player.hp / Cfg.maxHp).clamp(0.0, 1.0).toDouble();
    final Color barColor = csgoHpColor(ratio, alive: alive);

    return Opacity(
      // 阵亡灰显
      opacity: alive ? 1.0 : 0.5,
      child: Container(
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: CsColors.panel,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(
            color: isMe ? CsColors.accent : CsColors.border,
            width: isMe ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!alive) ...<Widget>[
                  const Icon(Icons.close, size: 10, color: CsColors.danger),
                  const SizedBox(width: 3),
                ],
                Expanded(
                  child: Text(
                    isMe ? '${player.name} · 我' : player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: isMe ? CsColors.accent : CsColors.textStrong,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: alive ? ratio : 0,
              minHeight: 4,
              backgroundColor: CsColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
            const SizedBox(height: 3),
            Text(
              alive ? '${player.hp} HP' : '阵亡',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
                color: alive ? barColor : CsColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部第一行：房间号 / 人数 / 房主重开按钮
class RoomHeader extends StatelessWidget {
  const RoomHeader({
    super.key,
    required this.roomId,
    required this.playerCount,
    required this.isHost,
    required this.onReset,
  });

  final String roomId;
  final int playerCount;
  final bool isHost;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: CsColors.panelDeep,
            borderRadius: BorderRadius.circular(1),
            border: Border.all(color: CsColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 5, height: 5, color: CsColors.accent),
              const SizedBox(width: 7),
              const Text(
                'ROOM',
                style: TextStyle(
                  color: CsColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                roomId.isEmpty ? '----' : roomId,
                style: const TextStyle(
                  color: CsColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· $playerCount/${Cfg.maxPlayers}',
                style: const TextStyle(
                  color: CsColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (isHost)
          TextButton.icon(
            onPressed: onReset,
            style: TextButton.styleFrom(
              backgroundColor: CsColors.panelDeep,
              foregroundColor: CsColors.accent,
              side: const BorderSide(color: CsColors.borderStrong),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('重置游戏'),
          ),
      ],
    );
  }
}
