import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:it_management_system/app.dart';
import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/log_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/theme_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';

/// The app exactly as main.dart builds it (same providers, same App).
Future<Widget> buildRealApp() async {
  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()..initialize()),
      ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),
      ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
      ChangeNotifierProvider<RequestProvider>(create: (_) => RequestProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<DeploymentProvider>(create: (_) => DeploymentProvider()),
      ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
    ],
    child: const App(),
  );
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));

    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for $finder');
}

Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String description = 'condition',
}) async {
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));

    if (condition()) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for $description');
}

/// Context below MaterialApp.router (has GoRouter and providers).
BuildContext routedContext(WidgetTester tester) {
  return tester.element(find.byType(Scaffold).first);
}

String currentPath(WidgetTester tester) {
  return GoRouter.of(routedContext(tester))
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

T readProvider<T>(WidgetTester tester) {
  return Provider.of<T>(tester.element(find.byType(App)), listen: false);
}

/// Collects framework errors (overflows, exceptions) with their messages so
/// failures report exactly what went wrong and where.
class ErrorCollector {
  ErrorCollector._(this._previous);

  final FlutterExceptionHandler? _previous;
  final List<String> messages = [];

  static ErrorCollector install() {
    final collector = ErrorCollector._(FlutterError.onError);

    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      final context = details.context?.toDescription() ?? '';
      collector.messages.add(
        '$text${context.isEmpty ? '' : ' ($context)'}'.split('\n').take(4).join(' | '),
      );
    };

    return collector;
  }

  List<String> drain() {
    final copy = List<String>.from(messages);
    messages.clear();
    return copy;
  }

  void restore() {
    FlutterError.onError = _previous;
  }
}
