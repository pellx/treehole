import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../widgets/app_app_bar.dart';

void navigateToSubPage(BuildContext context, String title, Widget body) {
  Navigator.of(context).push(MaterialPageRoute(builder: (ctx) {
    return Scaffold(
      backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppAppBar(
              title: title,
              onBack: () => Navigator.pop(ctx),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }));
}

Route<T> topDownRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
    transitionDuration: Duration(milliseconds: AppDimens.drawerAnimMs),
  );
}

Route<T> bottomUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
    transitionDuration: Duration(milliseconds: AppDimens.drawerAnimMs),
  );
}

void navigateToSettingsPage(BuildContext context, String title, Widget body) {
  Navigator.of(context).push(PageRouteBuilder(
    pageBuilder: (_, __, ___) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppAppBar(
                title: title,
                onBack: () => Navigator.pop(context),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    },
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position:
          Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
    transitionDuration: Duration(milliseconds: AppDimens.drawerAnimMs),
  ));
}
