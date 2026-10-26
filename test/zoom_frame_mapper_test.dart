import 'dart:ui';

import 'package:cs_cosplay/util/frame_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('原生变焦后的分析框与准星共用 contain 映射，不额外乘倍率', () {
    // 相机原生裁切后仍输出同尺寸帧；框的位置/大小由新帧检测决定。
    // 使用带左右黑边的取景区，检查框和命中采用同一偏移。
    final mapper = FrameMapper(
      frameSize: const Size(720, 1280),
      viewSize: const Size(400, 500),
    );
    const before = Rect.fromLTWH(320, 560, 80, 160);
    const after = Rect.fromLTWH(300, 520, 120, 240);
    expect(mapper.rectToView(before).contains(mapper.viewCenter), isTrue);
    expect(mapper.rectToView(after).contains(mapper.viewCenter), isTrue);
    expect(mapper.toView(const Offset(360, 640)), mapper.viewCenter);
    expect(
      mapper.visibleAreaRatio(after),
      closeTo(mapper.visibleAreaRatio(before) * 2.25, 0.000001),
    );
    const offCenter = Rect.fromLTWH(40, 520, 120, 240);
    expect(mapper.rectToView(offCenter).contains(mapper.viewCenter), isFalse);
    expect(mapper.imageRect.left, greaterThan(0));
  });
}
