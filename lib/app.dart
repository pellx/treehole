import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/main_shell.dart';
import 'app_navigator.dart';
import 'services/session_service.dart';
import 'services/storage.dart';
import 'theme/app_colors.dart';

final GlobalKey<TreeholeAppState> appKey = GlobalKey<TreeholeAppState>();
ThemeMode _themeMode = ThemeMode.system;

class TreeholeApp extends StatefulWidget {
  const TreeholeApp({super.key});

  static ThemeMode get themeMode => _themeMode;

  static void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    PostStorage.saveThemeMode(mode);
    appKey.currentState?.refresh();
  }

  @override
  State<TreeholeApp> createState() => TreeholeAppState();
}

class TreeholeAppState extends State<TreeholeApp> with WidgetsBindingObserver {
  void refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    _themeMode = PostStorage.getThemeMode();
    WidgetsBinding.instance.addObserver(this);
    _ensureSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 后台期间他机可能已解绑本机，回前台尽早清登录 / 切号，并重连 WS
      SessionService.instance.invalidate();
      _ensureSession();
    }
  }

  /// 启动与回前台时检测 session / 绑定有效性
  Future<void> _ensureSession() async {
    await SessionService.instance.ensureSession();
  }

  static const _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '树通',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
      ],
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: AppColors.commonLight.background,
        colorScheme: ColorScheme.light(
          primary: AppColors.commonLight.green,
          onPrimary: Colors.white,
          surface: AppColors.commonLight.surface,
          onSurface: AppColors.commonLight.onSurface,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.commonLight.green,
          selectionColor: AppColors.commonLight.green.withValues(alpha: 0.3),
          selectionHandleColor: AppColors.commonLight.green,
        ),
        pageTransitionsTheme: _transitions,
        extensions: const [AppColors.light],
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.commonDark.background,
        colorScheme: ColorScheme.dark(
          primary: AppColors.commonDark.green,
          onPrimary: Colors.black,
          surface: AppColors.commonDark.surface,
          onSurface: AppColors.commonDark.onSurface,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.commonDark.green,
          selectionColor: AppColors.commonDark.green.withValues(alpha: 0.3),
          selectionHandleColor: AppColors.commonDark.green,
        ),
        pageTransitionsTheme: _transitions,
        extensions: const [AppColors.dark],
      ),
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final bg = Theme.of(context).scaffoldBackgroundColor;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: bg,
            statusBarIconBrightness: brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
          ),
          child: child!,
        );
      },
      home: const MainShell(),
    );
  }
}
