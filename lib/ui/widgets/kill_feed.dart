import 'package:flutter/material.dart';

import '../../models/feed_item.dart';
import '../theme/csgo_theme.dart';

/// 战报：谁打了谁。被打的人也能从这里看到凶手是谁。
class KillFeed extends StatelessWidget {
  const KillFeed({super.key, required this.items});

  final List<FeedItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .take(3)
            .map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Color(0xCC1B1E19),
                  border: Border(
                    left: BorderSide(color: CsColors.accentDim, width: 2),
                  ),
                ),
                child: Text(
                  item.text,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: CsColors.text,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
