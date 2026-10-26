import 'package:flutter/material.dart';

import '../theme/csgo_theme.dart';

/// 固定在下方终端面板，不遮挡预览、准星或射击按钮。
class ZoomControls extends StatelessWidget {
  const ZoomControls({
    super.key,
    required this.zoom,
    required this.maxZoom,
    required this.enabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  final double zoom;
  final double maxZoom;
  final bool enabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CsColors.panelDeep,
        border: Border.all(color: CsColors.borderStrong),
        borderRadius: BorderRadius.circular(1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: '缩小',
            color: CsColors.accent,
            onPressed: enabled && zoom > 1.0 ? onDecrease : null,
            icon: const Icon(Icons.remove),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${zoom.toStringAsFixed(1)}x',
                semanticsLabel: '当前变焦 ${zoom.toStringAsFixed(1)} 倍',
                style: const TextStyle(
                  color: CsColors.accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '放大',
            color: CsColors.accent,
            onPressed: enabled && zoom < maxZoom ? onIncrease : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
