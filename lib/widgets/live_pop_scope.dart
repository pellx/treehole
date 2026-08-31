import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// [PopScope] 的实时求值版本。
///
/// [PopScope] 的 canPop 只在自身重建时更新；若拦截条件依赖「本页 setState
/// 之外的状态」（例如根 Overlay 上的图片预览开关），重建时机不可靠，返回
/// 手势/返回键会读到旧值，导致预览打开时整页被 pop。
///
/// 这里改为：
///  * 返回发生时实时调用 [canPop]（经由 [Route.popDisposition] 读取
///    [PopEntry.canPopNotifier.value]，不依赖任何重建）；
///  * [recomputeTrigger] 变化时通知 route 重新上报
///    [NavigationNotification]，使 Android 预测式返回的系统侧判定
///    （frameworkHandlesBack）与实时状态一致。
class LivePopScope extends StatefulWidget {
  const LivePopScope({
    super.key,
    required this.canPop,
    this.recomputeTrigger,
    this.onPopInvokedWithResult,
    required this.child,
  });

  /// 返回发生时实时调用；返回 true 表示允许 pop
  final bool Function() canPop;

  /// [canPop] 依赖的外部状态变化源；为空则不上报变化
  final Listenable? recomputeTrigger;

  final PopInvokedWithResultCallback<void>? onPopInvokedWithResult;

  final Widget child;

  @override
  State<LivePopScope> createState() => _LivePopScopeState();
}

class _LivePopScopeState extends State<LivePopScope> {
  ModalRoute<dynamic>? _route;
  late final _LivePopEntry _popEntry = _LivePopEntry(this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(_popEntry);
      _route = nextRoute;
      _route?.registerPopEntry(_popEntry);
    }
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(_popEntry);
    _route = null;
    _popEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _LivePopEntry extends ChangeNotifier
    implements PopEntry<void>, ValueListenable<bool> {
  _LivePopEntry(this._scope) {
    _scope.widget.recomputeTrigger?.addListener(notifyListeners);
  }

  final _LivePopScopeState _scope;

  @override
  bool get value => _scope.widget.canPop();

  @override
  ValueListenable<bool> get canPopNotifier => this;

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, void result) {
    _scope.widget.onPopInvokedWithResult?.call(didPop, result);
  }

  @override
  void dispose() {
    _scope.widget.recomputeTrigger?.removeListener(notifyListeners);
    super.dispose();
  }
}
