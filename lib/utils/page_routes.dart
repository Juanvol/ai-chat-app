// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

/// 弹性页面路由 — 带弹簧曲线的滑动+渐显过渡
class ElasticPageRoute<T> extends PageRouteBuilder<T> {
  ElasticPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.02, 0);
            const end = Offset.zero;
            final tween = Tween(begin: begin, end: end)
                .chain(CurveTween(curve: Curves.elasticOut));
            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
        );
}

/// 将弹性路由推到 Navigator 栈顶
Future<T?> pushElastic<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(ElasticPageRoute<T>(
    builder: (_) => page,
  ));
}
