import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/game_session.dart';
import 'ui/join_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 锁定竖屏。这样 ML Kit 的旋转补偿恒等于 sensorOrientation（后摄一般 90°），
  // 坐标映射只需要处理一种情况，最不容易出错。
  await SystemChrome.setPreferredOrientations(
    const <DeviceOrientation>[DeviceOrientation.portraitUp],
  );
  // 全屏沉浸，准星和绿框尽量占满画面
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00E676),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0B0F12),
        ),
        home: const JoinScreen(),
      ),
    );
  }
}
