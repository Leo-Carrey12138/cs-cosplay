import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/player.dart';
import '../team_style.dart';
import '../theme/csgo_theme.dart';

/// 命中后弹出「你打到了谁？」——一人一个大按钮，5 秒不操作自动取消。
///
/// [candidates] 已经由 GameSession 过滤为「存活的敌人」，这里只负责展示。
/// [serverNowMs] 用于显示复活保护状态，和开火判定使用同一个服务器时间基准。
Future<Player?> showTargetPicker(
  BuildContext context, {
  required List<Player> candidates,
  required double hitPercent,
  required int serverNowMs,
}) {
  return showModalBottomSheet<Player>(
    context: context,
    backgroundColor: CsColors.panel,
    barrierColor: const Color(0xA6000000),
    isDismissible: true,
    enableDrag: true,
    // 5 个人 × 60px 的大按钮会超过默认最大高度，必须允许自定义高度 + 可滚动
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
      side: BorderSide(color: CsColors.borderStrong),
    ),
    builder: (sheetContext) => _TargetPickerSheet(
      candidates: candidates,
      hitPercent: hitPercent,
      serverNowMs: serverNowMs,
    ),
  );
}

class _TargetPickerSheet extends StatefulWidget {
  const _TargetPickerSheet({
    required this.candidates,
    required this.hitPercent,
    required this.serverNowMs,
  });

  final List<Player> candidates;
  final double hitPercent;
  final int serverNowMs;

  @override
  State<_TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends State<_TargetPickerSheet> {
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    // 5 秒没点 → 自动取消（当作没打中）
    _timeoutTimer = Timer(Cfg.pickerTimeout, () {
      if (mounted) Navigator.of(context).pop<Player>(null);
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _select(Player player) {
    _timeoutTimer?.cancel();
    Navigator.of(context).pop<Player>(player);
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidates.take(5).toList();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 3,
                  color: CsColors.borderStrong,
                ),
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.center,
                child: CsgoTag(label: 'HIT CONFIRMED'),
              ),
              const SizedBox(height: 8),
              const Text(
                '命中！你打到了谁？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: CsColors.textStrong,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '目标占屏 ${widget.hitPercent.toStringAsFixed(1)}%（越大约近）· 5 秒内不选自动取消',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: CsColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 1, end: 0),
                duration: Cfg.pickerTimeout,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: CsColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(CsColors.accent),
                ),
              ),
              const SizedBox(height: 14),
              // 一人一行，大按钮好点
              for (var i = 0; i < candidates.length; i++)
                _TargetButton(
                  index: i,
                  player: candidates[i],
                  serverNowMs: widget.serverNowMs,
                  onPressed: () => _select(candidates[i]),
                ),
              TextButton(
                onPressed: () {
                  _timeoutTimer?.cancel();
                  Navigator.of(context).pop<Player>(null);
                },
                child: const Text(
                  '算了 / 没打中',
                  style: TextStyle(color: CsColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetButton extends StatelessWidget {
  const _TargetButton({
    required this.index,
    required this.player,
    required this.serverNowMs,
    required this.onPressed,
  });

  final int index;
  final Player player;
  final int serverNowMs;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final teamColor = TeamStyle.colorOf(player.team);
    final shielded = player.isInvincibleAt(serverNowMs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SizedBox(
        height: 60,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: CsColors.panelDeep,
            foregroundColor: CsColors.textStrong,
            side: BorderSide(color: teamColor, width: 1.2),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Row(
            children: <Widget>[
              Text(
                '0${index + 1}',
                style: const TextStyle(
                  color: CsColors.accentDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 9),
              // 队色徽标：A / B / ?
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: teamColor.withValues(alpha: 0.18),
                  border: Border.all(color: teamColor, width: 1),
                  borderRadius: BorderRadius.circular(1),
                ),
                child: Text(
                  TeamStyle.initialOf(player.team),
                  style: TextStyle(
                    color: teamColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: CsColors.textStrong,
                      ),
                    ),
                    Text(
                      '${player.team?.label ?? '未选队'} · ${player.kills} 击杀',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: CsColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (shielded) ...<Widget>[
                const Icon(
                  Icons.shield,
                  size: 15,
                  color: Color(0xFF40C4FF),
                ),
                const SizedBox(width: 3),
                const Text(
                  '复活保护',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF40C4FF),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                '${player.hp} HP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: csgoHpColor(
                    player.hp / Cfg.maxHp,
                    alive: player.isAlive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
