import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/player.dart';
import '../theme/csgo_theme.dart';

/// 命中后弹出「你打到了谁？」——一人一个大按钮，5 秒不操作自动取消。
Future<Player?> showTargetPicker(
  BuildContext context, {
  required List<Player> candidates,
  required double hitPercent,
}) {
  return showModalBottomSheet<Player>(
    context: context,
    backgroundColor: CsColors.panel,
    barrierColor: const Color(0xA6000000),
    isDismissible: true,
    enableDrag: true,
    // 5 个人 × 62px 的大按钮会超过默认最大高度，必须允许自定义高度 + 可滚动
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
      side: BorderSide(color: CsColors.borderStrong),
    ),
    builder: (sheetContext) => _TargetPickerSheet(
      candidates: candidates,
      hitPercent: hitPercent,
    ),
  );
}

class _TargetPickerSheet extends StatefulWidget {
  const _TargetPickerSheet(
      {required this.candidates, required this.hitPercent});

  final List<Player> candidates;
  final double hitPercent;

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
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: SizedBox(
                    height: 60,
                    child: FilledButton(
                      onPressed: () => _select(candidates[i]),
                      style: FilledButton.styleFrom(
                        backgroundColor: CsColors.panelDeep,
                        foregroundColor: CsColors.textStrong,
                        side: const BorderSide(
                          color: CsColors.accentDim,
                          width: 1.2,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(1)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '0${i + 1}',
                            style: const TextStyle(
                              color: CsColors.accentDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.person_outline,
                            color: CsColors.accent,
                            size: 20,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              candidates[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: CsColors.textStrong,
                              ),
                            ),
                          ),
                          Text(
                            '${candidates[i].hp} HP',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: csgoHpColor(
                                candidates[i].hp / Cfg.maxHp,
                                alive: candidates[i].isAlive,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
