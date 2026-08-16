import 'package:flutter/material.dart';

import 'client/views/main_shell_view/main_shell_view.dart';

void main() {
  runApp(const RasaRouteApp());
}

class RasaRouteApp extends StatelessWidget {
  const RasaRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rasa Route',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFFFF8E7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF9700),
          primary: const Color(0xFFFF9700),
          secondary: const Color(0xFFF0B400),
          surface: const Color(0xFFFFF8E7),
        ),
      ),
      home: const MainShellView(),
    );
  }
}
