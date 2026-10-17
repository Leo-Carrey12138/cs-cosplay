import 'package:flutter/material.dart';

import '../../models/feed_item.dart';

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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.text,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFFFAB91),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
