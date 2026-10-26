import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/game_session.dart';
import 'ui/join_screen.dart';
import 'ui/theme/csgo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 锁定竖屏。这样 ML Kit 的旋转补偿恒等于 sensorOrientation（后摄一般 90°），
  // 坐标映射只需要处理一种情况，最不容易出错。
  await SystemChrome.setPreferredOrientations(
    const <DeviceOrientation>[DeviceOrientation.portraitUp],
  );
  // 全屏沉浸，准星和绿框尽量占满画面
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // 系统栏临时滑出时也保持深色底 + 浅色图标，和战术终端主题一致
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: CsColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: CsColors.border,
    ),
  );

  // 读取 android/app/google-services.json
  await Firebase.initializeApp();

  runApp(const CsCosplayApp());
}

class CsCosplayApp extends StatelessWidget {
  const CsCosplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameSession>(
      create: (_) => GameSession(),
      child: MaterialApp(
        title: '真人 CS',
        debugShowCheckedModeBanner: false,
        theme: buildCsgoTheme(),
        home: const JoinScreen(),
      ),
    );
  }
}
