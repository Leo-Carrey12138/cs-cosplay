import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/player.dart';

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
      // 卡片内容实测高度 ≈ 48.2（名字行 ~19.2 + 4 + 进度条 5 + 3 + HP 文本 ~17），
      // Container 内边距上下各 5、边框上下各 1 → 需要 ≥ 60.2。
      // 取 64 留出余量，字体放大一档也不会溢出。
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
    final alive = player.isAlive;
    final ratio = (player.hp / 100).clamp(0.0, 1.0).toDouble();
    final barColor = !alive
        ? const Color(0xFF555555)
        : ratio > 0.6
            ? const Color(0xFF00E676)
            : ratio > 0.3
                ? const Color(0xFFFFC107)
                : const Color(0xFFFF5252);

    return Opacity(
      // 阵亡灰显
      opacity: alive ? 1.0 : 0.45,
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe ? const Color(0xFF00E676) : Colors.white24,
            width: isMe ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!alive)
                  const Icon(Icons.close, size: 11, color: Colors.white54),
                Expanded(
                  child: Text(
                    isMe ? '${player.name}(我)' : player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: alive ? ratio : 0,
                minHeight: 5,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              alive ? '${player.hp} HP' : '阵亡',
              style: TextStyle(
                fontSize: 10,
                color: alive ? Colors.white70 : Colors.white38,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '房间 $roomId · $playerCount/${Cfg.maxPlayers}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        const Spacer(),
        if (isHost)
          TextButton.icon(
            onPressed: onReset,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xCC000000),
              foregroundColor: const Color(0xFF00E676),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 34),
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重置游戏', style: TextStyle(fontSize: 12.5)),
          ),
      ],
    );
  }
}
