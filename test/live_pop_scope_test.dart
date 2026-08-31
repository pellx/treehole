// LivePopScope 回归测试：
// canPop 依赖外部状态（不经页面 setState/重建）变化时，
// 返回仍需被实时拦截；触发后回调收到 didPop=false。
// 注意：Navigator.maybePop 的返回值表示「框架消费了这次请求」，
// doNotPop（拦截）同样返回 true，故断言以页面是否离场与回调为准。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treehole/widgets/live_pop_scope.dart';

void main() {
  testWidgets(
    'LivePopScope blocks pop with zero rebuilds when canPop goes false',
    (tester) async {
      final ValueNotifier<bool> blocking = ValueNotifier<bool>(false);
      bool interceptCalled = false;

      final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: LivePopScope(
            recomputeTrigger: blocking,
            canPop: () => !blocking.value,
            onPopInvokedWithResult: (didPop, _) {
              interceptCalled = !didPop;
            },
            child: const Scaffold(body: Text('page')),
          ),
        ),
      );

      // 关键：不调用 setState / pumpWidget 重建页面，直接翻转外部状态
      blocking.value = true;
      await tester.pump(); // 只推进帧，页面 build 无变化

      await navKey.currentState!.maybePop();
      expect(find.text('page'), findsOneWidget,
          reason: 'canPop 实时为 false，路由不得被 pop');
      expect(interceptCalled, isTrue, reason: '应收到 didPop=false 的拦截回调');

      // 解除拦截后正常 pop
      blocking.value = false;
      await tester.pump();
      await navKey.currentState!.maybePop();
      expect(find.text('page'), findsNothing, reason: 'canPop 恢复后应正常离场');
    },
  );

  testWidgets('LivePopScope allows pop when canPop stays true', (tester) async {
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ),
    );

    await navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => LivePopScope(
          canPop: () => true,
          child: const Scaffold(body: Text('second')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await navKey.currentState!.maybePop();
    expect(find.text('second'), findsNothing, reason: 'canPop=true 应正常 pop');
    expect(find.text('home'), findsOneWidget);
  });
}
