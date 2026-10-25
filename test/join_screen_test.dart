import 'package:cs_cosplay/ui/join_screen.dart';
import 'package:cs_cosplay/ui/theme/csgo_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCsgoTheme(),
      home: const JoinScreen(),
    );

void main() {
  testWidgets('默认填入昵称和 4 位房间号', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    final TextField nickname =
        tester.widget<TextField>(find.byKey(const Key('nickname_field')));
    expect(nickname.controller, isNotNull);
    expect(nickname.controller!.text, matches(RegExp(r'^玩家\d{3}$')));

    final TextField room =
        tester.widget<TextField>(find.byKey(const Key('room_field')));
    expect(room.controller, isNotNull);
    expect(room.controller!.text, matches(RegExp(r'^\d{4}$')));
  });

  testWidgets('随机房号按钮会刷新房号并给出明确反馈', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.byKey(const Key('random_room_button')));
    await tester.pump();

    final TextField room =
        tester.widget<TextField>(find.byKey(const Key('room_field')));
    final String generated = room.controller!.text;
    expect(generated, matches(RegExp(r'^\d{4}$')));
    expect(find.text('已生成新房号 · $generated'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('已生成新房号 · $generated'), findsOneWidget);
  });

  testWidgets('空昵称会提示并阻止加入', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    await tester.enterText(find.byKey(const Key('nickname_field')), '   ');
    await tester.tap(find.byKey(const Key('join_button')));
    await tester.pump();

    expect(find.text('请输入昵称'), findsOneWidget);
  });

  testWidgets('房间号不足 4 位会提示', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    await tester.enterText(find.byKey(const Key('room_field')), '12');
    await tester.tap(find.byKey(const Key('join_button')));
    await tester.pump();

    expect(find.text('房间号必须是 4 位数字'), findsOneWidget);
  });

  testWidgets('小屏 + 键盘弹出时不溢出且可滚动到按钮', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('join_button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('join_button')), findsOneWidget);
  });

  testWidgets('常见手机尺寸下布局不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('真人 CS'), findsOneWidget);
    expect(find.text('加入战斗'), findsOneWidget);
  });
}
