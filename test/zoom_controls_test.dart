import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cs_cosplay/ui/widgets/zoom_controls.dart';

void main() {
  testWidgets('倍率显示与上下限、忙碌/不可用状态', (tester) async {
    var increases = 0;
    var decreases = 0;
    Future<void> show(double zoom, double max, bool enabled) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(
              zoom: zoom,
              maxZoom: max,
              enabled: enabled,
              onDecrease: () => decreases++,
              onIncrease: () => increases++,
            ),
          ),
        ),
      );
    }

    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip),
    );

    await show(1.0, 2.3, true);
    expect(find.text('1.0x'), findsOneWidget);
    expect(button('缩小').onPressed, isNull);
    await tester.tap(find.byTooltip('放大'));
    expect(increases, 1);

    await show(1.5, 2.3, true);
    expect(find.text('1.5x'), findsOneWidget);
    await tester.tap(find.byTooltip('缩小'));
    expect(decreases, 1);

    await show(2.3, 2.3, true);
    expect(button('放大').onPressed, isNull);
    await show(1.5, 2.3, false);
    expect(button('放大').onPressed, isNull);
    expect(button('缩小').onPressed, isNull);
    await show(1.0, 1.0, true);
    expect(button('放大').onPressed, isNull);
    expect(button('缩小').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
