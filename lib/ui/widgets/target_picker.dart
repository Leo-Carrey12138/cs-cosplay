import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/player.dart';

/// 命中后弹出「你打到了谁？」——一人一个大按钮，5 秒不操作自动取消。
Future<Player?> showTargetPicker(
  BuildContext context, {
  required List<Player> candidates,
  required double hitPercent,
}) {
  return showModalBottomSheet<Player>(
    context: context,
    backgroundColor: const Color(0xF212171C),
    isDismissible: true,
    enableDrag: true,
    // 5 个人 × 62px 的大按钮会超过默认最大高度，必须允许自定义高度 + 可滚动
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => _TargetPickerSheet(
      candidates: candidates,
      hitPercent: hitPercent,
    ),
  );
}

class _TargetPickerSheet extends StatefulWidget {
  const _TargetPickerSheet({required this.candidates, required this.hitPercent});

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '命中！你打到了谁？',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '目标占屏 ${widget.hitPercent.toStringAsFixed(1)}%（越大约近）· 5 秒内不选自动取消',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 1, end: 0),
                duration: Cfg.pickerTimeout,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 一人一行，大按钮好点
            ...candidates.map(
              (player) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: 62,
                  child: FilledButton(
                    onPressed: () => _select(player),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E2A32),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF00E676), width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.person, color: Color(0xFF00E676)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${player.hp} HP',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _timeoutTimer?.cancel();
                Navigator.of(context).pop<Player>(null);
              },
              child: const Text('算了 / 没打中', style: TextStyle(color: Colors.white54)),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
