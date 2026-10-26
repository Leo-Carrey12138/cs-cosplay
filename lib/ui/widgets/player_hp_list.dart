import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/player.dart';
import '../team_style.dart';
import '../theme/csgo_theme.dart';

/// 顶部：本房间所有玩家的血条列表（按队伍分组，名字 + HP + 击杀 + 状态）
class PlayerHpList extends StatefulWidget {
  const PlayerHpList({
    super.key,
    required this.players,
    required this.myId,
    required this.serverNow,
  });

  final List<Player> players;
  final String myId;

  /// 估算的服务器时间（复活倒计时 / 护盾倒计时都基于它）
  final int Function() serverNow;

  @override
  State<PlayerHpList> createState() => _PlayerHpListState();
}

class _PlayerHpListState extends State<PlayerHpList> {
  Timer? _ticker;

  bool get _needsTick => widget.players.any(
        (p) => p.isDead || p.isInvincibleAt(widget.serverNow()),
      );

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant PlayerHpList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (!_needsTick) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) {
        _ticker?.cancel();
        _ticker = null;
        return;
      }
      setState(() {});
      if (!_needsTick) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.serverNow();
    return SizedBox(
      // 横向列表定界：卡片内容 = 名字行 ~14 + 4 + 血条 4 + 3 + 状态行 ~12，
      // 加卡片上下内边距 10 + 边框 2，再留出字体缩放的余量 → 取 78。
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // 外层终端面板已经有 10px 内边距，这里不再叠加，保证血条卡片和
        // 房间号左对齐；3 个玩家时正好铺满，6 个玩家时横向滚动。
        padding: EdgeInsets.zero,
        itemCount: widget.players.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final player = widget.players[index];
          return _PlayerChip(
            player: player,
            isMe: player.id == widget.myId,
            serverNow: now,
          );
        },
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.player,
    required this.isMe,
    required this.serverNow,
  });

  final Player player;
  final bool isMe;
  final int serverNow;

  @override
  Widget build(BuildContext context) {
    final alive = player.isAlive;
    final ratio = (player.hp / Cfg.maxHp).clamp(0.0, 1.0).toDouble();
    final teamColor = TeamStyle.colorOf(player.team);
    final barColor = csgoHpColor(ratio, alive: alive);
    final shielded = player.isInvincibleAt(serverNow);

    final String statusText;
    if (!alive) {
      final deathAt = player.deathAt;
      if (deathAt == null) {
        statusText = '阵亡';
      } else {
        final remain = deathAt + Cfg.respawnDelay.inMilliseconds - serverNow;
        statusText = remain > 0 ? '重生 ${(remain / 1000).ceil()}s' : '阵亡';
      }
    } else if (shielded) {
      final remain = (player.invincibleUntil ?? 0) - serverNow;
      statusText = '保护 ${(remain / 1000).toStringAsFixed(1)}s';
    } else {
      statusText = '${player.hp} HP';
    }

    return Opacity(
      // 阵亡灰显
      opacity: alive ? 1.0 : 0.5,
      child: Container(
        width: 122,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: CsColors.panel,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(
            color: isMe ? CsColors.accent : teamColor.withValues(alpha: 0.55),
            width: isMe ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // 队色徽标：A / B / ?
                Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: teamColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(1),
                  ),
                  child: Text(
                    TeamStyle.initialOf(player.team),
                    style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: teamColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
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
                if (!alive) ...<Widget>[
                  const SizedBox(width: 2),
                  const Icon(Icons.close, size: 10, color: CsColors.danger),
                ],
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
            Row(
              children: <Widget>[
                if (shielded) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(
                      Icons.shield,
                      size: 10,
                      color: Color(0xFF40C4FF),
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.2,
                      color: alive ? CsColors.text : CsColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  'K ${player.kills}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: CsColors.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部第一行：房间号 / 队伍比分 / 房主重开按钮
class RoomHeader extends StatelessWidget {
  const RoomHeader({
    super.key,
    required this.roomId,
    required this.playerCount,
    required this.isHost,
    required this.onReset,
    this.alphaScore = 0,
    this.bravoScore = 0,
  });

  final String roomId;
  final int playerCount;
  final bool isHost;
  final VoidCallback onReset;
  final int alphaScore;
  final int bravoScore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: CsColors.panelDeep,
              borderRadius: BorderRadius.circular(1),
              border: Border.all(color: CsColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(width: 5, height: 5, color: CsColors.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'ROOM $roomId · $playerCount/${Cfg.maxPlayers}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CsColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: _TeamScoreBar(alpha: alphaScore, bravo: bravoScore),
        ),
        if (isHost) ...<Widget>[
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onReset,
            style: TextButton.styleFrom(
              backgroundColor: CsColors.panelDeep,
              foregroundColor: CsColors.accent,
              side: const BorderSide(color: CsColors.borderStrong),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('重置游戏'),
          ),
        ],
      ],
    );
  }
}

/// ALPHA 总击杀 : BRAVO 总击杀
class _TeamScoreBar extends StatelessWidget {
  const _TeamScoreBar({required this.alpha, required this.bravo});

  final int alpha;
  final int bravo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: CsColors.panelDeep,
        borderRadius: BorderRadius.circular(1),
        border: Border.all(color: CsColors.border),
      ),
      // 窄屏时整体等比缩小，避免比分条被固定字宽撑破。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'A',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: TeamStyle.alpha,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '$alpha',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: TeamStyle.alpha,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(':', style: TextStyle(color: CsColors.textMuted)),
            ),
            Text(
              '$bravo',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: TeamStyle.bravo,
              ),
            ),
            const SizedBox(width: 3),
            const Text(
              'B',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: TeamStyle.bravo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
